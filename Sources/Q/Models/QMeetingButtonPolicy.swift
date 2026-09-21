import Foundation

public enum QMeetingTriplePressAction: Equatable, Sendable {
    case useGlobalAssignment
    case toggleDiscordDeafen
}

public enum QMeetingButtonPolicy {
    public static func triplePressAction(
        hasActiveDiscordCall: Bool
    ) -> QMeetingTriplePressAction {
        guard hasActiveDiscordCall else {
            return .useGlobalAssignment
        }
        return .toggleDiscordDeafen
    }
}
