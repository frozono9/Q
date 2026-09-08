import AppKit
import ApplicationServices
import Foundation
import OSLog
import QCore

struct DiscordIntegrationSnapshot: Sendable {
    var state: QState
    var isDiscordRunning: Bool
}

actor DiscordLogScanner {
    private let fileManager = FileManager.default
    private var byteOffset: UInt64 = 0
    private var partialLine = Data()
    private var latestState: QState = .available

    func scan() -> QState {
        let logURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/discord/logs/renderer_js.log")

        guard let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
            reset()
            return .available
        }

        if fileSize < byteOffset {
            reset()
        }
        guard fileSize > byteOffset,
              let handle = try? FileHandle(forReadingFrom: logURL) else {
            return latestState
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: byteOffset)
            let appended = try handle.readToEnd() ?? Data()
            byteOffset = fileSize

            var buffer = partialLine
            buffer.append(appended)
            let hasTrailingNewline = buffer.last == 0x0A
            var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: true)
            if !hasTrailingNewline, let partial = lines.popLast() {
                partialLine = Data(partial)
            } else {
                partialLine = Data()
            }

            for line in lines {
                let text = String(decoding: line, as: UTF8.self)
                if let state = QDiscordRTCLogParser.state(from: text) {
                    latestState = state
                }
            }
        } catch {
            reset()
        }

        return latestState
    }

    private func reset() {
        byteOffset = 0
        partialLine = Data()
        latestState = .available
    }
}

@MainActor
final class DiscordLocalIntegration {
    private let scanner = DiscordLogScanner()
    private let logger = Logger(subsystem: "app.q", category: "discord-integration")
    private var monitoringTask: Task<Void, Never>?
    private var lastSnapshot: DiscordIntegrationSnapshot?

    var canControlDiscord: Bool {
        AXIsProcessTrusted()
    }

    func start(onUpdate: @escaping @MainActor @Sendable (DiscordIntegrationSnapshot) -> Void) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [scanner] in
            while !Task.isCancelled {
                let isRunning = Self.runningDiscord != nil
                let detectedState = isRunning ? await scanner.scan() : .available
                let snapshot = DiscordIntegrationSnapshot(
                    state: detectedState,
                    isDiscordRunning: isRunning
                )
                if snapshot.state != lastSnapshot?.state ||
                    snapshot.isDiscordRunning != lastSnapshot?.isDiscordRunning {
                    lastSnapshot = snapshot
                    logger.notice(
                        "Discord running=\(snapshot.isDiscordRunning) state=\(String(describing: snapshot.state), privacy: .public)"
                    )
                    onUpdate(snapshot)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func focusDiscord() {
        if let application = Self.runningDiscord {
            application.activate(options: [.activateAllWindows])
            return
        }

        let applicationURL = URL(fileURLWithPath: "/Applications/Discord.app")
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                self.logger.error("Could not open Discord: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Returns true only when the command can be delivered to Discord.
    func toggleMute() -> Bool {
        guard let application = Self.runningDiscord else {
            focusDiscord()
            return false
        }

        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }

        application.activate(options: [.activateAllWindows])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: false) else {
                return
            }
            let flags: CGEventFlags = [.maskCommand, .maskShift]
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private static var runningDiscord: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.hnc.Discord").first
    }
}

extension DiscordIntegrationSnapshot: Equatable {}
