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
    private var lastRequestedMicrophoneState: QMicrophoneState?

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
                if snapshot.state == .available {
                    lastRequestedMicrophoneState = nil
                }
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

    func toggleMute() async -> QMeetingControlResult {
        let observed = await observedMicrophoneState()
        let current = if observed != .unknown {
            observed
        } else if let lastRequestedMicrophoneState {
            lastRequestedMicrophoneState
        } else {
            Self.microphoneState(from: lastSnapshot?.state)
        }
        guard current != .unknown else { return .failed }
        return await setMuted(current == .unmuted)
    }

    func setMuted(_ shouldMute: Bool) async -> QMeetingControlResult {
        guard let application = Self.runningDiscord else {
            focusDiscord()
            return .unavailable
        }
        guard lastSnapshot?.state == .meeting || lastSnapshot?.state == .muted else {
            return .unavailable
        }
        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return .permissionDenied
        }

        let desired: QMicrophoneState = shouldMute ? .muted : .unmuted
        let before = await observedMicrophoneState()
        logger.notice(
            "Control requested desired=\(desired.rawValue, privacy: .public) observed=\(before.rawValue, privacy: .public)"
        )
        if before == desired {
            lastRequestedMicrophoneState = desired
            return .confirmed(desired)
        }

        let pressed = await Task.detached(priority: .userInitiated) {
            QMeetingAccessibilitySurface.pressMicrophoneButton(
                processIdentifier: application.processIdentifier,
                shouldMute: shouldMute
            )
        }.value
        if !pressed {
            // Target Discord itself. This avoids stealing focus and removes
            // the race between activation and Electron accepting its shortcut.
            guard Self.postMuteShortcut(to: application.processIdentifier) else { return .failed }
        }

        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(125))
            if await observedMicrophoneState() == desired {
                lastRequestedMicrophoneState = desired
                return .confirmed(desired)
            }
        }
        lastRequestedMicrophoneState = desired
        return .sentUnconfirmed
    }

    private func observedMicrophoneState() async -> QMicrophoneState {
        guard let application = Self.runningDiscord else { return .unknown }
        return await Task.detached(priority: .utility) {
            QMeetingAccessibilitySurface(
                processIdentifier: application.processIdentifier
            ).microphoneState()
        }.value
    }

    private static func microphoneState(from state: QState?) -> QMicrophoneState {
        switch state {
        case .muted: .muted
        case .meeting: .unmuted
        default: .unknown
        }
    }

    private static func postMuteShortcut(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: false) else {
            return false
        }
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }

    private static var runningDiscord: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.hnc.Discord").first
    }
}

extension DiscordIntegrationSnapshot: Equatable {}
