import Foundation

public enum QContextualHold: Equatable, Sendable {
    case meeting(QMeetingProvider)
    case dictation
    case none

    public static func resolve(mode: QMode, meeting: QMeetingSession?) -> Self {
        switch mode {
        case .aiAgents:
            return .dictation
        case .meetings:
            guard let meeting, meeting.isActive else { return .none }
            return .meeting(meeting.provider)
        default:
            return .none
        }
    }
}
