import Foundation

enum QFirmwareUpdateState: Equatable {
    case idle
    case preparing
    case flashing(progress: Double?)
    case reconnecting
    case succeeded
    case failed(String)

    var isRunning: Bool {
        switch self {
        case .preparing, .flashing, .reconnecting: true
        default: false
        }
    }
}

struct QFirmwareUpdater {
    static let currentVersion = "0.2.3"

    enum UpdateError: LocalizedError {
        case missingTool
        case missingFirmware
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingTool:
                "The bundled Q firmware tool is missing. Reinstall Q and try again."
            case .missingFirmware:
                "The bundled Q firmware image is missing. Reinstall Q and try again."
            case let .processFailed(message):
                "Firmware update failed. \(message)"
            }
        }
    }

    func flash(portPath: String, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let tool = try toolURL()
        let firmware = try firmwareURL()
        let process = Process()
        let output = Pipe()
        process.executableURL = tool
        process.arguments = [
            "--skip-update-check", "write-bin", "--chip", "esp32c3",
            "--port", portPath, "--non-interactive", "0x0", firmware.path
        ]
        process.standardOutput = output
        process.standardError = output

        let reader = output.fileHandleForReading
        let collector = QFirmwareOutputCollector(progress: progress)
        reader.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.consume(data)
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            throw UpdateError.processFailed(error.localizedDescription)
        }
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        reader.readabilityHandler = nil
        collector.consume(reader.readDataToEndOfFile())
        guard process.terminationStatus == 0 else {
            throw UpdateError.processFailed(collector.summary)
        }
        progress(1)
    }

    private func toolURL() throws -> URL {
        if let bundled = Bundle.main.url(forResource: "espflash", withExtension: nil, subdirectory: "Updater") {
            return bundled
        }
        let developmentPaths = [
            "/opt/homebrew/bin/espflash",
            "/usr/local/bin/espflash"
        ]
        if let path = developmentPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw UpdateError.missingTool
    }

    private func firmwareURL() throws -> URL {
        if let bundled = Bundle.main.url(
            forResource: "Q-Firmware-\(Self.currentVersion)",
            withExtension: "bin",
            subdirectory: "Updater"
        ) {
            return bundled
        }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Updater/Q-Firmware-\(Self.currentVersion).bin")
        guard FileManager.default.fileExists(atPath: development.path) else {
            throw UpdateError.missingFirmware
        }
        return development
    }
}

private final class QFirmwareOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let progress: @Sendable (Double?) -> Void

    init(progress: @escaping @Sendable (Double?) -> Void) {
        self.progress = progress
    }

    func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > 24_000 { data.removeFirst(data.count - 24_000) }
        let text = String(decoding: data, as: UTF8.self)
        lock.unlock()

        let pattern = #"(\d{1,3}(?:\.\d+)?)%"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
           let range = Range(match.range(at: 1), in: text),
           let value = Double(text[range]) {
            progress(min(max(value / 100, 0), 1))
        } else {
            progress(nil)
        }
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.suffix(800))
    }
}
