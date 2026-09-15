import Foundation
import Testing
@testable import QCore

@Suite("Q USB serial protocol")
struct QSerialProtocolTests {
    @Test func encodesHeartbeatWithProtocolVersion() throws {
        let command = try #require(String(data: QSerialProtocol.heartbeatCommand, encoding: .utf8))
        #expect(command == "P|1\n")
    }

    @Test func encodesExactlyThreeLEDsWithNormalBrightnessSemantics() throws {
        let scene = QScene(
            name: "Hardware test",
            leds: [
                QLEDState(color: .red, brightness: 1),
                QLEDState(color: .green, brightness: 0.5, animation: .fadeInOut),
                .off
            ]
        )

        let command = try #require(String(data: QSerialProtocol.sceneCommand(scene), encoding: .utf8))
        let fields = command.trimmingCharacters(in: .newlines).split(separator: "|", omittingEmptySubsequences: false)

        #expect(fields.count == 4)
        #expect(fields[0] == "S")
        #expect(fields[1] == "255,31,31,255,1,0,1000,0")
        #expect(fields[2] == "38,230,89,128,1,5,1000,0")
        #expect(fields[3] == "255,255,255,0,0,0,1000,0")
    }

    @Test func decodesPhysicalButtonEvents() {
        #expect(QSerialProtocol.buttonEvent(from: "B|single\r\n") == .singlePress)
        #expect(QSerialProtocol.buttonEvent(from: "B|double") == .doublePress)
        #expect(QSerialProtocol.buttonEvent(from: "B|long") == .longPress)
        #expect(QSerialProtocol.buttonEvent(from: "Q|1") == nil)
    }
}
