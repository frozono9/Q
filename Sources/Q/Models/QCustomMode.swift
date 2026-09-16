import Foundation

public enum QCustomActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case inheritGlobal
    case none
    case nextState
    case previousState
    case turnOff
    case openURL
    case openApplication
    case runShortcut

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .inheritGlobal: "Use Q default"
        case .none: "No action"
        case .nextState: "Next state"
        case .previousState: "Previous state"
        case .turnOff: "Turn LEDs off"
        case .openURL: "Open URL"
        case .openApplication: "Open application"
        case .runShortcut: "Run Apple Shortcut"
        }
    }

    public var requiresValue: Bool {
        switch self {
        case .openURL, .openApplication, .runShortcut: true
        default: false
        }
    }

    public var valuePlaceholder: String {
        switch self {
        case .openURL: "https://example.com"
        case .openApplication: "com.example.App or App name"
        case .runShortcut: "Shortcut name"
        default: ""
        }
    }
}

public struct QCustomAction: Codable, Equatable, Sendable {
    public var kind: QCustomActionKind
    public var value: String

    public init(kind: QCustomActionKind = .inheritGlobal, value: String = "") {
        self.kind = kind
        self.value = value
    }
}

public struct QCustomButtonMapping: Codable, Equatable, Sendable {
    public var singlePress: QCustomAction
    public var doublePress: QCustomAction
    public var longPress: QCustomAction

    public init(
        singlePress: QCustomAction = QCustomAction(kind: .nextState),
        doublePress: QCustomAction = QCustomAction(kind: .inheritGlobal),
        longPress: QCustomAction = QCustomAction(kind: .inheritGlobal)
    ) {
        self.singlePress = singlePress
        self.doublePress = doublePress
        self.longPress = longPress
    }

    public func action(for trigger: QButtonTrigger) -> QCustomAction {
        switch trigger {
        case .singlePress: singlePress
        case .doublePress: doublePress
        case .longPress: longPress
        }
    }
}

public struct QCustomStateDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var scene: QScene
    public var buttonMapping: QCustomButtonMapping

    public init(
        id: UUID = UUID(),
        name: String,
        scene: QScene,
        buttonMapping: QCustomButtonMapping = QCustomButtonMapping()
    ) {
        self.id = id
        self.name = name
        self.scene = scene
        self.buttonMapping = buttonMapping
    }
}

public struct QCustomModeDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var systemImage: String
    public var isIncludedInCycle: Bool
    public var states: [QCustomStateDefinition]
    public var defaultStateID: UUID

    public init(
        id: UUID = UUID(),
        name: String,
        systemImage: String = "slider.horizontal.3",
        isIncludedInCycle: Bool = true,
        states: [QCustomStateDefinition],
        defaultStateID: UUID? = nil
    ) {
        let normalizedStates = states.isEmpty ? [Self.defaultState()] : states
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.isIncludedInCycle = isIncludedInCycle
        self.states = normalizedStates
        self.defaultStateID = defaultStateID.flatMap { candidate in
            normalizedStates.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? normalizedStates[0].id
    }

    public static func draft() -> QCustomModeDefinition {
        let state = defaultState()
        return QCustomModeDefinition(
            name: "My Mode",
            states: [state],
            defaultStateID: state.id
        )
    }

    private static func defaultState() -> QCustomStateDefinition {
        QCustomStateDefinition(
            name: "Default",
            scene: QScene(
                name: "Default",
                leds: Array(
                    repeating: QLEDState(color: .green, brightness: 0.85),
                    count: QScene.ledCount
                )
            )
        )
    }
}
