import Foundation

public enum QCodexActivityKind: String, Codable, Sendable {
    case started
    case resumed
    case needsUser
    case completed
    case failed
}

public struct QCodexActivityEvent: Codable, Equatable, Sendable {
    public var kind: QCodexActivityKind
    public var date: Date

    public init(kind: QCodexActivityKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

public enum QCodexActivityResolver {
    public static func state(for events: [QCodexActivityEvent]) -> QState? {
        guard let latest = events.max(by: { $0.date < $1.date }) else { return nil }

        switch latest.kind {
        case .started, .resumed:
            return .working
        case .needsUser:
            return .waitingForUser
        case .completed:
            return .done
        case .failed:
            return .error
        }
    }

    public static func shouldReplace(
        _ current: QCodexActivityEvent?,
        with candidate: QCodexActivityEvent
    ) -> Bool {
        guard let current else { return true }
        if current.kind == .needsUser, candidate.kind == .completed {
            return false
        }
        return current.date <= candidate.date
    }
}

public enum QCodexPromptClassifier {
    public static func requestsUserInput(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }

        if normalized.hasSuffix("?") {
            return true
        }

        return [
            "need your input",
            "need your approval",
            "please confirm",
            "please choose",
            "waiting for your input",
            "waiting for your approval",
            "authorize this"
        ].contains { normalized.contains($0) }
    }
}

public enum QCodexSessionDiscovery {
    /// Finds recently active rollouts regardless of the date directory in which
    /// Codex originally created the task. Old tasks can be resumed at any time.
    public static func recentRolloutFiles(
        in root: URL,
        now: Date = .now,
        activeWithin interval: TimeInterval
    ) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) <= interval else { continue }
            results.append(url)
        }
        return results
    }
}
