import Foundation

public enum QGestureAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case contextual
    case nextMode
    case nextState
    case showStatus
    case none

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .contextual: "Contextual action"
        case .nextMode: "Next mode"
        case .nextState: "Next state"
        case .showStatus: "Show status"
        case .none: "No action"
        }
    }
}

public struct QGestureSettings: Codable, Equatable, Sendable {
    public var singlePress: QGestureAction
    public var doublePress: QGestureAction
    public var longPress: QGestureAction

    public init(
        singlePress: QGestureAction = .contextual,
        doublePress: QGestureAction = .nextMode,
        longPress: QGestureAction = .none
    ) {
        self.singlePress = singlePress
        self.doublePress = doublePress
        self.longPress = longPress
    }
}
