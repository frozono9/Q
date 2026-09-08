import Foundation

public enum QState: Codable, Equatable, Hashable, Sendable {
    case idle
    case working
    case waitingForUser
    case permissionRequired
    case done
    case error
    case meeting
    case muted
    case presenting
    case recording
    case focus
    case available
    case away
    case busy
    case offline
    case pomodoroFocus
    case pomodoroBreak
    case paused
    case finished
    case building
    case testing
    case passed
    case failed
    case deploying
    case deployed
    case custom(String)
}
