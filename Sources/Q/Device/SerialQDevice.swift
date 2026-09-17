import Combine
import Foundation
import OSLog

private final class QSerialWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: FileHandle?

    func attach(_ handle: FileHandle) {
        lock.lock()
        self.handle = handle
        lock.unlock()
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { throw QDeviceError.notConnected }
        try handle.write(contentsOf: data)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.close()
        handle = nil
    }
}

@MainActor
public final class SerialQDevice: ObservableObject, QDevice {
    public let id = "physical-q"
    public let name = "Q"

    @Published public private(set) var isConnected = false
    @Published public private(set) var currentScene: QScene = .idle
    @Published public private(set) var portPath: String?
    @Published public private(set) var firmwareVersion: String?
    @Published public private(set) var deviceIdentifier: String?

    public let buttonEvents: AsyncStream<QButtonEvent>

    private let buttonContinuation: AsyncStream<QButtonEvent>.Continuation
    private var handle: FileHandle?
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "app.q.serial-heartbeat", qos: .utility)
    private let serialWriter = QSerialWriter()
    private var receiveBuffer = Data()
    private var receivedReady = false
    private let logger = Logger(subsystem: "app.q", category: "serial-device")

    public init() {
        let stream = AsyncStream<QButtonEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        buttonEvents = stream.stream
        buttonContinuation = stream.continuation
    }

    deinit {
        heartbeatTimer?.cancel()
        handle?.readabilityHandler = nil
        serialWriter.close()
        buttonContinuation.finish()
    }

    public func connect() async throws {
        guard !isConnected else { return }
        let paths = Self.availablePortPaths()
        guard !paths.isEmpty else {
            throw QDeviceError.noSerialDevice
        }

        for path in paths {
            do {
                try Self.configure(path: path)
                let opened = try FileHandle(forUpdating: URL(fileURLWithPath: path))
                receivedReady = false
                receiveBuffer.removeAll(keepingCapacity: true)
                opened.readabilityHandler = { [weak self] readable in
                    let data = readable.availableData
                    Task { @MainActor [weak self] in
                        self?.receive(data)
                    }
                }
                handle = opened
                serialWriter.attach(opened)
                portPath = path

                // USB-UART bridges commonly reset the ESP32-C3 when opened.
                // Wait for boot, then request a protocol response so Q never
                // mistakes an unrelated serial accessory for the device.
                try await Task.sleep(for: .milliseconds(800))
                try opened.write(contentsOf: Data("H|\(QSerialProtocol.version)\n".utf8))
                try await Task.sleep(for: .milliseconds(350))
                guard receivedReady else {
                    throw QDeviceError.serialConnection("No Q handshake from \(path).")
                }

                isConnected = true
                try await apply(scene: currentScene)
                startHeartbeat()
                logger.notice("Physical Q connected at \(path, privacy: .public)")
                return
            } catch {
                disconnectNow()
            }
        }
        throw QDeviceError.serialConnection("USB serial devices were found, but none identified as Q.")
    }

    public func disconnect() async {
        disconnectNow()
    }

    public func apply(scene: QScene) async throws {
        guard isConnected else { throw QDeviceError.notConnected }
        try write(QSerialProtocol.sceneCommand(scene))
        currentScene = scene
    }

    public func setLED(index: Int, state: QLEDState) async throws {
        guard currentScene.leds.indices.contains(index) else {
            throw QDeviceError.invalidLEDIndex(index)
        }
        var scene = currentScene
        scene.leds[index] = state
        try await apply(scene: scene)
    }

    public static func availablePortPaths() -> [String] {
        let prefixes = [
            "cu.usbmodem", "cu.usbserial", "cu.wchusbserial",
            "cu.SLAB_USBtoUART", "cu.usbUART"
        ]
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return entries
            .filter { entry in prefixes.contains { entry.hasPrefix($0) } }
            .map { "/dev/\($0)" }
            .sorted()
    }

    private static func configure(path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/stty")
        process.arguments = ["-f", path, "115200", "raw", "-echo"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw QDeviceError.serialConnection("Could not configure \(path).")
        }
    }

    private func write(_ data: Data) throws {
        do {
            try serialWriter.write(data)
        } catch {
            disconnectNow()
            throw QDeviceError.serialConnection(error.localizedDescription)
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else {
            logger.notice("Physical Q disconnected")
            disconnectNow()
            return
        }
        receiveBuffer.append(data)
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let lineData = receiveBuffer[..<newline]
            receiveBuffer.removeSubrange(...newline)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let message = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let info = QSerialProtocol.deviceInfo(from: message),
               info.protocolVersion == QSerialProtocol.version {
                firmwareVersion = info.firmwareVersion
                deviceIdentifier = info.deviceIdentifier
                receivedReady = true
            } else if QSerialProtocol.isHeartbeatChallenge(message) {
                do {
                    try serialWriter.write(QSerialProtocol.heartbeatCommand)
                } catch {
                    logger.error("Q heartbeat challenge response failed: \(error.localizedDescription, privacy: .public)")
                    disconnectNow()
                }
            } else if let event = QSerialProtocol.buttonEvent(from: message) {
                buttonContinuation.yield(event)
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let writer = serialWriter
        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            do {
                try writer.write(QSerialProtocol.heartbeatCommand)
            } catch {
                let reason = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.isConnected else { return }
                    self.logger.error("Q heartbeat failed: \(reason, privacy: .public)")
                    self.disconnectNow()
                }
            }
        }
        heartbeatTimer = timer
        timer.resume()
    }

    private func disconnectNow() {
        heartbeatTimer?.setEventHandler {}
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        handle?.readabilityHandler = nil
        serialWriter.close()
        handle = nil
        receiveBuffer.removeAll(keepingCapacity: true)
        receivedReady = false
        portPath = nil
        firmwareVersion = nil
        deviceIdentifier = nil
        isConnected = false
    }
}
