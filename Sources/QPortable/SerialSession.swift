import Foundation
import QCore

/// Bounds incomplete lines, drops an entire overlong/invalid line, then resumes
/// at the next newline. A suffix of discarded input can never become a command.
public struct SerialLineDecoder {
    private var bytes = [UInt8]()
    private var discarding = false
    private let limit: Int
    public init(limit: Int = 1024) { self.limit = max(1, limit) }

    public mutating func append(_ data: Data) -> [String] {
        var result = [String]()
        for byte in data {
            if byte == 10 {
                if !discarding, let line = String(bytes: bytes, encoding: .utf8) {
                    result.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                bytes.removeAll(keepingCapacity: true)
                discarding = false
            } else if !discarding {
                if bytes.count < limit { bytes.append(byte) }
                else { bytes.removeAll(keepingCapacity: true); discarding = true }
            }
        }
        return result
    }
}

public final class SerialSession {
    public let path: String
    public private(set) var info: QDeviceInfo?
    public var onButton: ((QButtonEvent) -> Void)?
    private let io: SerialIO
    private let now: () -> TimeInterval
    private var decoder = SerialLineDecoder()
    private var heartbeatAt: TimeInterval = 0
    private var receivedAck = false
    private var awaitingAck = false
    private var connected = false

    public init(path: String, io: SerialIO, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.path = path; self.io = io; self.now = now
    }

    public func handshake(timeout: TimeInterval = 5) throws -> QDeviceInfo {
        let deadline = now() + timeout
        // USB CDC can reset on open. Discard the initial boot banner before
        // asking for identity, so its delayed response cannot look like a reset.
        let settleUntil = min(deadline, now() + 0.8)
        while now() < settleUntil { _ = try io.read(timeoutMilliseconds: 100) }
        var helloAt = -TimeInterval.infinity
        while now() < deadline {
            if now() - helloAt >= 1 {
                try io.write(Data("H|\(QSerialProtocol.version)\n".utf8))
                helloAt = now()
            }
            try receive()
            if let info {
                guard info.protocolVersion == QSerialProtocol.version else {
                    throw QTransportError.message("Unsupported Q protocol \(info.protocolVersion); expected \(QSerialProtocol.version)")
                }
                guard let id = info.deviceIdentifier, id.hasPrefix("Q-"), id.count > 2 else {
                    throw QTransportError.message("Q did not report a stable device ID; automatic selection is unsafe")
                }
                connected = true
                try heartbeat()
                return info
            }
        }
        throw QTransportError.message("No Q handshake on \(path) within \(Int(timeout)) seconds")
    }

    public func poll() throws {
        guard connected else { throw QTransportError.message("Q is not connected") }
        if now() - heartbeatAt >= 1 { try heartbeat() }
        try receive()
    }

    public func apply(_ scene: QScene, timeout: TimeInterval = 2) throws {
        guard connected else { throw QTransportError.message("Q is not connected") }
        // Drain input before starting a new transaction, so an old A|scene
        // already queued in the OS cannot acknowledge this scene.
        try poll()
        receivedAck = false
        awaitingAck = true
        defer { awaitingAck = false }
        try io.write(QSerialProtocol.sceneCommand(scene))
        let deadline = now() + timeout
        while now() < deadline {
            try poll()
            if receivedAck { return }
        }
        throw QTransportError.message("Q did not acknowledge the scene")
    }

    private func heartbeat() throws {
        try io.write(QSerialProtocol.heartbeatCommand)
        heartbeatAt = now()
    }

    private func receive() throws {
        for line in decoder.append(try io.read(timeoutMilliseconds: 100)) {
            if let identity = QSerialProtocol.deviceInfo(from: line) {
                if connected {
                    // A spontaneous boot banner means the device restarted.
                    // Reconnect and reapply through the normal identity check.
                    throw QTransportError.message("Q restarted; reconnecting")
                }
                info = identity
            } else if QSerialProtocol.isHeartbeatChallenge(line) {
                try heartbeat()
            } else if let button = QSerialProtocol.buttonEvent(from: line) {
                onButton?(button)
            } else if line == "A|scene", awaitingAck {
                receivedAck = true
            } else if line.hasPrefix("E|"), awaitingAck {
                throw QTransportError.message("Q rejected the command: \(line)")
            }
        }
    }

    public func close() { connected = false; io.close() }
    deinit { close() }
}

public struct QSelection {
    public var port: String?
    public var deviceID: String?
    public init(port: String? = nil, deviceID: String? = nil) { self.port = port; self.deviceID = deviceID }
}

public enum QDiscovery {
    public static func connect(
        selection: QSelection,
        candidates: () throws -> [String] = NativeSerialIO.candidates,
        open: (String) throws -> SerialIO = { try NativeSerialIO(path: $0) },
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) throws -> SerialSession {
        let paths = try selection.port.map { [$0] } ?? candidates()
        var matches = [SerialSession]()
        var failures = [String]()
        for path in paths {
            var session: SerialSession?
            do {
                let candidate = SerialSession(path: path, io: try open(path), now: now)
                session = candidate
                let info = try candidate.handshake()
                if let expected = selection.deviceID, info.deviceIdentifier != expected {
                    failures.append("\(path): different Q (\(info.deviceIdentifier ?? "unknown"))")
                    candidate.close()
                } else {
                    matches.append(candidate)
                }
            } catch {
                session?.close()
                failures.append("\(path): \(error.localizedDescription)")
            }
        }
        guard matches.count == 1 else {
            matches.forEach { $0.close() }
            if matches.count > 1 {
                throw QTransportError.message("Multiple Q devices found; choose --id or --port: " + matches.map { "\($0.info?.deviceIdentifier ?? "unknown") at \($0.path)" }.joined(separator: ", "))
            }
            throw QTransportError.message("No matching Q found. " + (failures.isEmpty ? "Connect Q with a USB data cable." : failures.joined(separator: "; ")))
        }
        return matches[0]
    }
}

/// Reconnection is pinned to the first verified ID, even if its COM/tty changes.
public final class QClient {
    public private(set) var session: SerialSession?
    public private(set) var deviceID: String?
    public private(set) var scene: QScene?
    public var onButton: ((QButtonEvent) -> Void)?
    public var onConnection: ((String) -> Void)?
    private var selection: QSelection
    private let connectSession: (QSelection) throws -> SerialSession
    private let now: () -> TimeInterval
    private var retryAt: TimeInterval = 0
    private var hadConnection = false

    public init(selection: QSelection, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                connect: @escaping (QSelection) throws -> SerialSession = { try QDiscovery.connect(selection: $0) }) {
        self.selection = selection; self.connectSession = connect; self.now = now
    }

    public func connect() throws {
        let next = try connectSession(selection)
        guard let id = next.info?.deviceIdentifier, next.info?.protocolVersion == QSerialProtocol.version,
              deviceID == nil || deviceID == id else {
            next.close(); throw QTransportError.message("Reconnect returned the wrong Q identity")
        }
        next.onButton = { [weak self] event in self?.onButton?(event) }
        do { if let scene { try next.apply(scene) } }
        catch { next.close(); throw error }
        session = next; deviceID = id; selection.deviceID = id
        // An explicit initial port is only a discovery hint after identification.
        selection.port = nil
        onConnection?("\(hadConnection ? "Reconnected" : "Connected") \(id) on \(next.path)")
        hadConnection = true
    }

    public func apply(_ value: QScene) throws {
        guard let session else { throw QTransportError.message("Q is disconnected") }
        do { try session.apply(value); scene = value }
        catch {
            // A scene with an uncertain acknowledgement must not leave a live
            // session that could mistake its delayed ack for the next command.
            session.close(); self.session = nil; retryAt = now() + 2
            throw error
        }
    }

    public func poll() {
        if let session {
            do { try session.poll() }
            catch {
                session.close(); self.session = nil; retryAt = now() + 2
                onConnection?("Disconnected: \(error.localizedDescription)")
            }
        } else if now() >= retryAt {
            do { try connect() }
            catch { retryAt = now() + 2; onConnection?("Waiting for \(deviceID ?? "Q"): \(error.localizedDescription)") }
        }
    }

    public func close() { session?.close(); session = nil }
    deinit { close() }
}
