import Foundation

public enum QButtonAction: Codable, Equatable, Sendable {
    case changeScene(UUID)
    case cycleScene
    case turnOff
    case toggleAutomaticManual
    case changeBrightness(Double)
    case toggleFocusMode
    case lockMac
    case focusSource
    case cycleActiveSources
    case acknowledge
    case interruptSource
    case toggleMeetingMute
    case raiseHand
    case focusMeetingApplication
    case startPomodoro
    case togglePomodoro
    case skipPomodoro
    case cancelPomodoro
    case toggleManualStatus
    case openApplication(String)
    case openURL(URL)
    case mediaPlayPause
    case openBuild
    case retryBuild
    case runShellCommand(String)
    case runShortcut(String)
    case webhook(URL)
    case localHTTPRequest(url: URL, method: String)
    case custom(String)
    case none
}

public enum QButtonTrigger: String, Codable, CaseIterable, Sendable {
    case singlePress
    case doublePress
    case longPress
}

public struct QButtonMapping: Codable, Equatable, Sendable {
    public var singlePress: QButtonAction
    public var doublePress: QButtonAction
    public var longPress: QButtonAction

    public init(
        singlePress: QButtonAction = .none,
        doublePress: QButtonAction = .none,
        longPress: QButtonAction = .none
    ) {
        self.singlePress = singlePress
        self.doublePress = doublePress
        self.longPress = longPress
    }

    public func action(for trigger: QButtonTrigger) -> QButtonAction {
        switch trigger {
        case .singlePress: singlePress
        case .doublePress: doublePress
        case .longPress: longPress
        }
    }
}

public struct QContextualButtonRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var state: QState
    public var mapping: QButtonMapping

    public init(id: UUID = UUID(), state: QState, mapping: QButtonMapping) {
        self.id = id
        self.state = state
        self.mapping = mapping
    }
}
