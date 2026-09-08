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
}
