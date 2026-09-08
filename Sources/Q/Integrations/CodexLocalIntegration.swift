import AppKit
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
    private let completedRetentionInterval: TimeInterval = 5 * 60
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

    private func recentSessionFiles(in root: URL, now: Date) -> [URL] {
        let calendar = Calendar(identifier: .gregorian)
        let days = [now, calendar.date(byAdding: .day, value: -1, to: now)].compactMap { $0 }
        var results: [URL] = []

        for day in days {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayNumber = parts.day else { continue }
            let directory = root
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", dayNumber), isDirectory: true)

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true,
                      let modifiedAt = values.contentModificationDate,
                      now.timeIntervalSince(modifiedAt) <= activeStaleInterval else { continue }
                results.append(url)
            }
        }

        return results
    }

    private func session(from fileURL: URL, now: Date) -> QAgentSession? {
        do {
            let rollout = try updateRolloutCache(for: fileURL)
            guard let latest = rollout.latestActivity,
                  let state = QCodexActivityResolver.state(for: [latest]) else { return nil }

            if (state == .done || state == .error),
               now.timeIntervalSince(latest.date) > completedRetentionInterval {
                return nil
            }

            let projectName = URL(fileURLWithPath: rollout.metadata.cwd).lastPathComponent
            let displayName = projectName.isEmpty ? "Codex" : projectName
            return QAgentSession(
                id: rollout.metadata.id,
                source: "Codex / ChatGPT",
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
        var cached: CachedRollout
        if let existing = rolloutCache[fileURL] {
            cached = existing
        } else {
            cached = CachedRollout(
                metadata: try readMetadata(from: fileURL),
                byteOffset: 0,
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
            if cached.latestActivity == nil || cached.latestActivity!.date <= date {
                cached.latestActivity = activity
            }
        }
        rolloutCache[fileURL] = cached
        return cached
    }

    private func isPotentialActivityRecord(_ text: String) -> Bool {
        [
            "task_started", "task_complete", "task_failed", "turn/started", "turn/completed",
            "approval", "request_user_input", "userinput", "elicitation", "custom_tool_call_output",
            "usermessage", "fatal_error"
        ].contains { text.contains($0) }
    }

    private func activityKind(recordType: String?, payload: [String: Any]) -> QCodexActivityKind? {
        let payloadType = (payload["type"] as? String ?? "").lowercased()
        let item = payload["item"] as? [String: Any]
        let itemType = (item?["type"] as? String ?? "").lowercased()
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
    }

    func focus(_ session: QAgentSession?) {
        let deepLink = session?.context["deepLink"] ?? "codex://"
        guard let url = URL(string: deepLink) else { return }
        NSWorkspace.shared.open(url)
    }
}
