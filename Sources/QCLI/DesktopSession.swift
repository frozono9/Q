import Foundation
import QCore
import QPortable
import QSerialNative

private struct DesktopRequest: Decodable {
    var operation: String
    var stateID: String?
    var brightness: Double?
}

/// Only the pipe reader runs off-thread. All device operations and model
/// mutations stay on the session loop, including physical button actions.
private final class InputMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var lines = [Data]()
    private var finished = false
    func read() {
        var pending = Data()
        defer { lock.lock(); finished = true; lock.unlock() }
        do {
            while let data = try FileHandle.standardInput.read(upToCount: 4096), !data.isEmpty {
                for byte in data {
                    if byte == 10 {
                        lock.lock()
                        if lines.count >= 64 { lock.unlock(); return }
                        lines.append(pending); lock.unlock(); pending.removeAll(keepingCapacity: true)
                    } else {
                        guard pending.count < 8192 else { return }
                        pending.append(byte)
                    }
                }
            }
        } catch { return }
    }
    func take() -> ([Data], Bool) {
        lock.lock(); defer { lock.unlock() }
        let result = lines; lines.removeAll(keepingCapacity: true)
        return (result, finished)
    }
}

final class DesktopSession {
    private let store: PortablePreferencesStore
    private var preferences: PortablePreferences
    private let client: QClient
    private var connection = "Looking for Q…"
    private var errorMessage = ""
    private var lastGesture = ""
    private var gestureSequence = 0
    private var dirty = true
    private var needsApply = true
    private var pendingPresses = 0
    private var readyAt: TimeInterval = 0
    private var testIndex: Int?
    private var testAt: TimeInterval = 0
    private let testColors = ["red", "green", "blue", "white", "traffic"]
    private var appliedScene: QScene?

    init(options: CLIOptions) throws {
        let path = options.settingsPath!
        #if os(Windows)
        guard path.hasPrefix("\\\\") || (path.count > 2 && path.dropFirst().hasPrefix(":\\")) || (path.count > 2 && path.dropFirst().hasPrefix(":/")) else {
            throw QTransportError.message("Settings path must be absolute")
        }
        #else
        guard path.hasPrefix("/") else { throw QTransportError.message("Settings path must be absolute") }
        #endif
        store = PortablePreferencesStore(url: URL(fileURLWithPath: path))
        preferences = try store.load()
        var selection = options.selection
        if selection.deviceID == nil { selection.deviceID = preferences.deviceID }
        client = QClient(selection: selection)
    }

    private func persist(_ value: PortablePreferences) throws {
        try store.save(value)
        preferences = value
        needsApply = true; dirty = true; errorMessage = ""
    }

    private func press() throws {
        var next = preferences
        next.stateID = QAvailability.stateAfterPress(next.stateID)
        testIndex = nil
        try persist(next)
    }

    private func handle(_ data: Data) throws {
        let request = try JSONDecoder().decode(DesktopRequest.self, from: data)
        var next = preferences
        switch request.operation {
        case "snapshot": dirty = true
        case "setState":
            guard let id = request.stateID else { throw QTransportError.message("Missing state") }
            next.stateID = id; try next.validate()
            try persist(next); testIndex = nil
        case "setBrightness":
            guard let value = request.brightness else { throw QTransportError.message("Missing brightness") }
            next.brightness = value; try next.validate()
            try persist(next); testIndex = nil
        case "press": try press()
        case "test":
            guard client.session != nil else { throw QTransportError.message("Connect Q to test its lights") }
            testIndex = 0; needsApply = true; testAt = 0; dirty = true
        case "cancelTest": testIndex = nil; needsApply = true; dirty = true
        default: throw QTransportError.message("Unknown desktop operation")
        }
    }

    private func snapshot() {
        let scene = appliedScene ?? preferences.scene
        QCommand.json([
            "type": "snapshot", "protocolVersion": 1, "mode": "availability",
            "stateID": preferences.stateID, "stateName": preferences.preset.name,
            "brightness": preferences.brightness,
            "connected": client.session != nil, "connection": connection,
            "deviceID": client.deviceID ?? preferences.deviceID ?? "",
            "firmware": client.session?.info?.firmwareVersion ?? "",
            "port": client.session?.path ?? "", "error": errorMessage,
            "gesture": lastGesture, "gestureSequence": gestureSequence, "testing": testIndex != nil,
            "testColor": testIndex.map { testColors[$0] } ?? "",
            "applied": client.session != nil && !needsApply,
            "states": QModeCatalog.availability.states.map { ["id": $0.id, "name": $0.name, "color": $0.scene.leds[0].color.hex] },
            "leds": scene.leds.map { ["color": $0.color.hex, "brightness": $0.brightness, "enabled": $0.isEnabled] as [String: Any] }
        ])
        dirty = false
    }

    func run() throws {
        q_install_interrupt_handler()
        let input = InputMailbox()
        Thread.detachNewThread { input.read() }
        client.onConnection = { [unowned self] message in
            connection = message; dirty = true
            if client.session != nil {
                readyAt = ProcessInfo.processInfo.systemUptime + 2.2
                needsApply = true; errorMessage = ""
                if preferences.deviceID != client.deviceID {
                    var next = preferences; next.deviceID = client.deviceID
                    do { try persist(next) } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        client.onButton = { [unowned self] event in
            lastGesture = event.rawValue; gestureSequence += 1; dirty = true
            if event == .singlePress { pendingPresses += 1 }
        }
        defer {
            if client.session != nil { try? client.apply(.idle) }
            client.close()
        }
        snapshot()
        while q_interrupted() == 0 {
            let (lines, ended) = input.take()
            for line in lines {
                do { try handle(line) } catch { errorMessage = error.localizedDescription; dirty = true }
            }
            if ended { break }
            client.poll()
            while pendingPresses > 0 {
                pendingPresses -= 1
                do { try press() } catch { errorMessage = error.localizedDescription; dirty = true }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if let index = testIndex, testAt > 0, now >= testAt {
                testIndex = index + 1 < testColors.count ? index + 1 : nil
                needsApply = true; dirty = true; testAt = 0
            }
            if needsApply, client.session != nil, now >= readyAt {
                do {
                    let scene: QScene
                    if let index = testIndex {
                        var options = try CLIOptions(["test"])
                        options.color = testColors[index]; options.brightness = preferences.brightness
                        scene = try options.scene()
                    } else { scene = preferences.scene }
                    try client.apply(scene)
                    appliedScene = scene; needsApply = false; dirty = true
                    if testIndex != nil { testAt = now + 3 }
                } catch {
                    errorMessage = error.localizedDescription; connection = "Waiting for Q to reconnect"; dirty = true
                }
            }
            if dirty { snapshot() }
            if client.session == nil { Thread.sleep(forTimeInterval: 0.05) }
        }
    }
}
