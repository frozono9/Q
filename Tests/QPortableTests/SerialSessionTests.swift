import Foundation
import Testing
import QCore
@testable import QPortable

private final class Clock {
    var time: Double = 0
    func now() -> Double { time }
}

private final class FakeSerial: SerialIO {
    let clock: Clock
    var incoming = [Data]()
    var writes = [String]()
    var identity: String
    var acknowledge = true
    var reject = false
    var failRead = false
    var closed = false
    init(_ clock: Clock, id: String = "Q-one", version: Int = 1) {
        self.clock = clock; identity = "Q|\(version)|0.2.2|\(id)\n"
    }
    func read(timeoutMilliseconds: Int) throws -> Data {
        clock.time += Double(timeoutMilliseconds) / 1000
        if failRead { throw QTransportError.message("unplugged") }
        return incoming.isEmpty ? Data() : incoming.removeFirst()
    }
    func write(_ data: Data) throws {
        let line = String(decoding: data, as: UTF8.self)
        writes.append(line)
        if line.hasPrefix("H|") { incoming.append(Data(identity.utf8)) }
        if line.hasPrefix("S|") {
            if reject { incoming.append(Data("E|scene\n".utf8)) }
            else if acknowledge { incoming.append(Data("A|scene\n".utf8)) }
        }
    }
    func close() { closed = true }
}

struct SerialSessionTests {
    @Test func fragmentedCRLFLinesAndMultipleEvents() {
        var decoder = SerialLineDecoder()
        #expect(decoder.append(Data("B|lon".utf8)).isEmpty)
        #expect(decoder.append(Data("g\r\nB|long-release\n".utf8)) == ["B|long", "B|long-release"])
    }

    @Test func overlongAndInvalidUTF8LinesCannotBecomeCommands() {
        var decoder = SerialLineDecoder(limit: 16)
        #expect(decoder.append(Data(repeating: 65, count: 100_000)).isEmpty)
        #expect(decoder.append(Data("A|scene\nB|single\n".utf8)) == ["B|single"])
        #expect(decoder.append(Data([255, 10]) + Data("A|scene\n".utf8)) == ["A|scene"])
    }

    @Test func verifiesIdentityAndRejectsUnsupportedProtocol() throws {
        let clock = Clock()
        let io = FakeSerial(clock, version: 2)
        let session = SerialSession(path: "test", io: io, now: clock.now)
        #expect(throws: QTransportError.self) { try session.handshake() }
        #expect(!io.writes.contains { $0.hasPrefix("S|") })
    }

    @Test func heartbeatsAndAllButtonEventsWhileWaitingForAck() throws {
        let clock = Clock()
        let io = FakeSerial(clock)
        let session = SerialSession(path: "test", io: io, now: clock.now)
        _ = try session.handshake()
        var events = [QButtonEvent]()
        session.onButton = { events.append($0) }
        io.incoming.append(Data("C|heartbeat\nB|single\nB|double\nB|triple\nB|long\nB|long-release\n".utf8))
        try session.apply(.working)
        #expect(events == [.singlePress, .doublePress, .triplePress, .longPress, .longPressEnded])
        let previous = io.writes.count
        clock.time += 1.1
        try session.poll()
        #expect(io.writes.count == previous + 1)
        #expect(io.writes.last == "P|1\n")
    }

    @Test func staleAcknowledgementDoesNotSatisfyANewScene() throws {
        let clock = Clock()
        let io = FakeSerial(clock)
        // Use the I/O clock so timeout progresses with every simulated read.
        let session = SerialSession(path: "test", io: io, now: io.clock.now)
        _ = try session.handshake()
        io.incoming.append(Data("A|scene\n".utf8))
        io.acknowledge = false
        #expect(throws: QTransportError.self) { try session.apply(.working, timeout: 0.5) }
    }

    @Test func sceneRejectionIsAnError() throws {
        let clock = Clock()
        let io = FakeSerial(clock)
        let session = SerialSession(path: "test", io: io, now: clock.now)
        _ = try session.handshake()
        io.reject = true
        #expect(throws: QTransportError.self) { try session.apply(.working) }
    }

    @Test func aDeviceResetInvalidatesTheSession() throws {
        let clock = Clock()
        let io = FakeSerial(clock)
        let session = SerialSession(path: "test", io: io, now: clock.now)
        _ = try session.handshake()
        io.incoming.append(Data(io.identity.utf8))
        #expect(throws: QTransportError.self) { try session.poll() }
    }

    @Test func multipleDevicesRequireSelectionAndCloseBothPorts() {
        let clock = Clock()
        let first = FakeSerial(clock, id: "Q-one"), second = FakeSerial(clock, id: "Q-two")
        #expect(throws: QTransportError.self) {
            try QDiscovery.connect(selection: QSelection(), candidates: { ["one", "two"] },
                                   open: { $0 == "one" ? first : second }, now: clock.now)
        }
        #expect(first.closed && second.closed)
    }

    @Test func explicitIDSelectsOnlyTheMatchingUnit() throws {
        let clock = Clock()
        let first = FakeSerial(clock, id: "Q-one"), second = FakeSerial(clock, id: "Q-two")
        let selected = try QDiscovery.connect(selection: QSelection(deviceID: "Q-two"), candidates: { ["one", "two"] },
                                              open: { $0 == "one" ? first : second }, now: clock.now)
        #expect(selected.info?.deviceIdentifier == "Q-two")
        #expect(first.closed && !second.closed)
        selected.close()
    }

    @Test func reconnectPinsIdentityAndRestoresAcknowledgedScene() throws {
        let clock = Clock()
        let first = FakeSerial(clock), second = FakeSerial(clock)
        var selections = [QSelection]()
        let client = QClient(selection: QSelection(port: "old"), now: clock.now) { selection in
            selections.append(selection)
            let io = selections.count == 1 ? first : second
            let session = SerialSession(path: selections.count == 1 ? "old" : "new", io: io, now: clock.now)
            _ = try session.handshake()
            return session
        }
        try client.connect()
        try client.apply(.working)
        first.failRead = true
        client.poll()
        #expect(client.session == nil && first.closed)
        clock.time += 2.1
        client.poll()
        #expect(client.session?.path == "new")
        #expect(selections.last?.deviceID == "Q-one" && selections.last?.port == nil)
        #expect(second.writes.contains(String(decoding: QSerialProtocol.sceneCommand(.working), as: UTF8.self)))
    }

    @Test func rejectsWrongIdentityOnReconnect() throws {
        let clock = Clock()
        let first = FakeSerial(clock), other = FakeSerial(clock, id: "Q-other")
        var count = 0
        let client = QClient(selection: QSelection(), now: clock.now) { _ in
            count += 1
            let io = count == 1 ? first : other
            let session = SerialSession(path: "port", io: io, now: clock.now)
            _ = try session.handshake(); return session
        }
        try client.connect(); try client.apply(.working)
        first.failRead = true; client.poll(); clock.time += 3; client.poll()
        #expect(client.session == nil && other.closed)
        #expect(!other.writes.contains { $0.hasPrefix("S|") })
    }

    @Test func CLIRejectsInvalidArgumentsBeforeOpeningHardware() throws {
        for args in [["lights", "pink"], ["lights", "--brightness", "nan"], ["watch", "--seconds", "inf"],
                     ["status", "--seconds", "1"], ["lights", "--port"], ["off", "--port", "a", "--port", "b"]] {
            #expect(throws: QTransportError.self) { try CLIOptions(args) }
        }
        let valid = try CLIOptions(["lights", "traffic", "--seconds", "3", "--brightness", "0.4", "--id", "Q-one"])
        #expect(valid.seconds == 3 && valid.selection.deviceID == "Q-one")
        #expect(try valid.scene().leds.count == 3)
    }
}
