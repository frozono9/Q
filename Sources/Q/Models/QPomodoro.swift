import Foundation

public struct QPomodoroConfiguration: Codable, Equatable, Sendable {
    public static let commonFocusDurations = [15, 25, 30, 45, 60, 90]

    public var focusMinutes: Int
    public var breakMinutes: Int

    public init(focusMinutes: Int = 25, breakMinutes: Int = 5) {
        self.focusMinutes = min(max(focusMinutes, 1), 180)
        self.breakMinutes = min(max(breakMinutes, 1), 60)
    }
}

public enum QAvailabilityControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case manual

    public var name: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual override"
        }
    }
}
