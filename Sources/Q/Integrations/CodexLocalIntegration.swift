import AppKit
import ApplicationServices
import Foundation
import OSLog
import QCore

struct CodexIntegrationSnapshot: Sendable {
    var sessions: [QAgentSession]
    var isAvailable: Bool
}

actor CodexSessionScanner {
    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let logger = Logger(subsystem: "app.q", category: "codex-scanner")
    private let activeStaleInterval: TimeInterval = 2 * 60 * 60
    /// Completion is an event, not an active agent. Keep it just long enough to
    /// be noticed before freeing the LED slot for the live set.
    private let completedRetentionInterval: TimeInterval = 10
    private let errorRetentionInterval: TimeInterval = 5 * 60
    private let initialTailBytes: UInt64 = 1_048_576
    private var rolloutCache: [URL: CachedRollout] = [:]

    func scan(now: Date = .now) -> CodexIntegrationSnapshot {
        let codexDirectory = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sessionsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return CodexIntegrationSnapshot(sessions: [], isAvailable: false)
        }

        let candidateFiles = recentSessionFiles(in: sessionsDirectory, now: now)
        let sessions = candidateFiles.compactMap { session(from: $0, now: now) }
        return CodexIntegrationSnapshot(sessions: sessions, isAvailable: true)
    }

    func mostRecentSession() -> QAgentSession? {
        let sessionsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        let files = QCodexSessionDiscovery.recentRolloutFiles(
            in: sessionsDirectory,
            activeWithin: .greatestFiniteMagnitude
        )
        guard let file = files.max(by: { modificationDate(of: $0) < modificationDate(of: $1) }),
              let metadata = try? readMetadata(from: file) else {
            return nil
        }
        let modifiedAt = modificationDate(of: file)
        let projectName = URL(fileURLWithPath: metadata.cwd).lastPathComponent
        return QAgentSession(
            id: metadata.id,
            source: "Codex",
            displayName: projectName.isEmpty ? "Codex" : projectName,
            state: .idle,
            context: [
                "threadID": metadata.id,
                "cwd": metadata.cwd,
                "deepLink": "codex://threads/\(metadata.id)"
            ],
            updatedAt: modifiedAt
        )
    }

    private func recentSessionFiles(in root: URL, now: Date) -> [URL] {
        QCodexSessionDiscovery.recentRolloutFiles(
            in: root,
            now: now,
            activeWithin: activeStaleInterval
        )
    }

    private func modificationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    private func session(from fileURL: URL, now: Date) -> QAgentSession? {
        do {
            let rollout = try updateRolloutCache(for: fileURL)
            guard let latest = rollout.latestActivity,
                  let state = QCodexActivityResolver.state(for: [latest]) else { return nil }

            if state == .done,
               now.timeIntervalSince(latest.date) > completedRetentionInterval {
                return nil
            }
            if state == .error,
               now.timeIntervalSince(latest.date) > errorRetentionInterval {
                return nil
            }

            let projectName = URL(fileURLWithPath: rollout.metadata.cwd).lastPathComponent
            let displayName = projectName.isEmpty ? "Codex" : projectName
            return QAgentSession(
                id: rollout.metadata.id,
                source: "Codex",
                displayName: displayName,
                state: state,
                context: [
                    "threadID": rollout.metadata.id,
                    "cwd": rollout.metadata.cwd,
                    "deepLink": "codex://threads/\(rollout.metadata.id)"
                ],
                updatedAt: latest.date
            )
        } catch {
            logger.error("Skipped Codex rollout \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func readMetadata(from fileURL: URL) throws -> SessionMetadata {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1_024) ?? Data()
        guard let newline = data.firstIndex(of: 0x0A) else { throw ScannerError.invalidMetadata }
        let object = try jsonObject(from: data[..<newline])
        guard object["type"] as? String == "session_meta",
              let payload = object["payload"] as? [String: Any],
              let id = (payload["id"] ?? payload["session_id"]) as? String,
              let cwd = payload["cwd"] as? String else {
            throw ScannerError.invalidMetadata
        }
        return SessionMetadata(id: id, cwd: cwd)
    }

    private func updateRolloutCache(for fileURL: URL) throws -> CachedRollout {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let isInitialRead = rolloutCache[fileURL] == nil
        let initialOffset = fileSize > initialTailBytes ? fileSize - initialTailBytes : 0
        var cached: CachedRollout
        if let existing = rolloutCache[fileURL] {
            cached = existing
        } else {
            cached = CachedRollout(
                metadata: try readMetadata(from: fileURL),
                byteOffset: initialOffset,
                partialLine: Data(),
                latestActivity: nil
            )
        }

        if fileSize < cached.byteOffset {
            cached.byteOffset = 0
            cached.partialLine = Data()
            cached.latestActivity = nil
        }
        guard fileSize > cached.byteOffset else { return cached }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: cached.byteOffset)
        let appendedData = try handle.readToEnd() ?? Data()
        cached.byteOffset = fileSize

        var buffer = cached.partialLine
        buffer.append(appendedData)
        if isInitialRead, initialOffset > 0 {
            if let newline = buffer.firstIndex(of: 0x0A) {
                buffer.removeSubrange(...newline)
            } else {
                buffer.removeAll()
            }
        }
        let hasTrailingNewline = buffer.last == 0x0A
        var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: true)
        if !hasTrailingNewline, let partial = lines.popLast() {
            cached.partialLine = Data(partial)
        } else {
            cached.partialLine = Data()
        }

        for line in lines {
            let text = String(decoding: line, as: UTF8.self).lowercased()
            guard isPotentialActivityRecord(text) else { continue }
            guard let object = try? jsonObject(from: line),
                  let timestampText = object["timestamp"] as? String,
                  let date = dateFormatter.date(from: timestampText),
                  let payload = object["payload"] as? [String: Any],
                  let kind = activityKind(recordType: object["type"] as? String, payload: payload) else {
                continue
            }
            let activity = QCodexActivityEvent(kind: kind, date: date)
            if QCodexActivityResolver.shouldReplace(cached.latestActivity, with: activity) {
                cached.latestActivity = activity
            }
        }
        if cached.latestActivity == nil,
           let modifiedAt = attributes[.modificationDate] as? Date {
            // A long active turn may have pushed task_started outside the tail.
            // Recent writes are still reliable evidence that this task is working.
            cached.latestActivity = QCodexActivityEvent(kind: .started, date: modifiedAt)
        }
        rolloutCache[fileURL] = cached
        return cached
    }

    private func isPotentialActivityRecord(_ text: String) -> Bool {
        [
            "task_started", "task_complete", "task_failed", "turn/started", "turn/completed",
            "approval", "request_user_input", "userinput", "elicitation", "custom_tool_call_output",
            "usermessage", "agentmessage", "final_answer", "fatal_error"
        ].contains { text.contains($0) }
    }

    private func activityKind(recordType: String?, payload: [String: Any]) -> QCodexActivityKind? {
        let payloadType = (payload["type"] as? String ?? "").lowercased()
        let item = payload["item"] as? [String: Any]
        let itemType = (item?["type"] as? String ?? "").lowercased()
        let phase = (item?["phase"] as? String ?? "").lowercased()
        let toolName = (payload["name"] as? String ?? item?["name"] as? String ?? "").lowercased()
        let status = (payload["status"] as? String ?? item?["status"] as? String ?? "").lowercased()

        if payloadType == "task_started" || payloadType == "turn/started" { return .started }
        if payloadType == "task_complete" || payloadType == "turn/completed" {
            return status == "failed" ? .failed : .completed
        }
        if payloadType.contains("task_failed") || payloadType.contains("turn_failed") || payloadType == "fatal_error" {
            return .failed
        }

        let attentionMarker = [payloadType, itemType, toolName].joined(separator: " ")
        if attentionMarker.contains("approval") ||
            attentionMarker.contains("request_user_input") ||
            attentionMarker.contains("userinput") ||
            attentionMarker.contains("elicitation") {
            return .needsUser
        }

        if payloadType == "item_completed",
           itemType == "agentmessage",
           phase == "final_answer",
           let content = item?["content"] as? [[String: Any]] {
            let message = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if QCodexPromptClassifier.requestsUserInput(message) {
                return .needsUser
            }
        }

        if payloadType == "custom_tool_call_output" ||
            (payloadType == "item_completed" && itemType == "usermessage") {
            return .resumed
        }
        return nil
    }

    private func jsonObject(from data: some DataProtocol) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(data)) as? [String: Any] else {
            throw ScannerError.invalidJSON
        }
        return object
    }

    private struct SessionMetadata {
        var id: String
        var cwd: String
    }

    private struct CachedRollout {
        var metadata: SessionMetadata
        var byteOffset: UInt64
        var partialLine: Data
        var latestActivity: QCodexActivityEvent?
    }

    private enum ScannerError: Error {
        case invalidMetadata
        case invalidJSON
    }
}

@MainActor
final class CodexLocalIntegration {
    private let scanner = CodexSessionScanner()
    private let logger = Logger(subsystem: "app.q", category: "codex-integration")
    private var monitoringTask: Task<Void, Never>?
    private var dictationStartTask: Task<Void, Never>?
    private var dictationShortcutIsDown = false
    private var lastSnapshotSignature = ""

    func start(onUpdate: @escaping @MainActor @Sendable (CodexIntegrationSnapshot) -> Void) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [scanner] in
            while !Task.isCancelled {
                let snapshot = await scanner.scan()
                let signature = snapshot.sessions
                    .map { "\($0.id):\($0.state)" }
                    .sorted()
                    .joined(separator: ",")
                if signature != lastSnapshotSignature {
                    lastSnapshotSignature = signature
                    logger.notice("Codex live sessions: \(signature, privacy: .public)")
                }
                onUpdate(snapshot)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        endDictation()
    }

    func focus(_ session: QAgentSession?) {
        let deepLink = session?.context["deepLink"] ?? "codex://"
        guard let url = URL(string: deepLink) else { return }
        NSWorkspace.shared.open(url)
    }

    func focusMostRecentChat() {
        Task { @MainActor [weak self, scanner] in
            let session = await scanner.mostRecentSession()
            self?.focus(session)
        }
    }

    func openNewChat() {
        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }

        if Self.runningCodex == nil,
           let url = URL(string: "codex://") {
            NSWorkspace.shared.open(url)
        }
        Task { @MainActor [weak self] in
            for _ in 0..<20 {
                if let application = Self.runningCodex {
                    application.activate(options: [.activateAllWindows])
                    try? await Task.sleep(for: .milliseconds(120))
                    if Self.postNewChatShortcut(to: application.processIdentifier) {
                        self?.logger.notice("Opened a new Codex chat")
                    } else {
                        self?.logger.error("Could not invoke Codex's newTask command")
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            self?.logger.error("Could not open a new chat because Codex did not launch")
        }
    }

    func startDictation(in session: QAgentSession?) {
        guard AXIsProcessTrusted() else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }

        endDictation()
        focus(session)
        dictationStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // The firmware reports the long press while the physical button is still down.
            // Allow the deep link to focus its task, then hold Codex's own shortcut until release.
            do {
                try await Task.sleep(for: .milliseconds(120))
            } catch {
                return
            }
            guard let application = Self.runningCodex else {
                logger.error("Could not start dictation because Codex is not running")
                return
            }
            application.activate(options: [.activateAllWindows])
            try? await Task.sleep(for: .milliseconds(40))
            guard Self.postDictationKey(isDown: true) else {
                logger.error("Could not invoke Codex's composer.startDictation command")
                return
            }
            dictationShortcutIsDown = true
            logger.notice("Started Codex composer.startDictation hold")
        }
    }

    func endDictation() {
        dictationStartTask?.cancel()
        dictationStartTask = nil
        guard dictationShortcutIsDown else { return }
        if Self.postDictationKey(isDown: false) {
            logger.notice("Ended Codex composer.startDictation hold")
        } else {
            logger.error("Could not release Codex's composer.startDictation command")
        }
        dictationShortcutIsDown = false
    }

    private static var runningCodex: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first
    }

    /// Holds Codex's built-in Control-Shift-D binding for `composer.startDictation`.
    /// This deliberately avoids macOS Dictation and does not depend on window coordinates.
    private static func postDictationKey(isDown: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: 2, // D
            keyDown: isDown
        ) else { return false }
        event.flags = [.maskControl, .maskShift]
        event.post(tap: .cghidEventTap)
        return true
    }

    /// Codex registers Command-N as its `newTask` command and allows the
    /// accelerator while its window is hidden. Addressing the event directly
    /// to Codex avoids whichever app happened to be frontmost receiving it.
    private static func postNewChatShortcut(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }
}
