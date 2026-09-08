import Foundation

public enum QMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case aiAgents
    case availability
    case meetings
    case pomodoro
    case builds
    case custom

    public var id: String { rawValue }

    public static let primaryModes: [QMode] = [
        .aiAgents,
        .availability,
        .meetings,
        .pomodoro
    ]

    public var name: String {
        switch self {
        case .aiAgents: "AI Agents"
        case .availability: "Availability"
        case .meetings: "Meetings"
        case .pomodoro: "Pomodoro"
        case .builds: "Builds"
        case .custom: "Custom"
        }
    }

    public var systemImage: String {
        switch self {
        case .aiAgents: "sparkles"
        case .availability: "person.crop.circle.badge.checkmark"
        case .meetings: "video"
        case .pomodoro: "timer"
        case .builds: "hammer"
        case .custom: "slider.horizontal.3"
        }
    }

    /// States owned by live integrations are observable, not user-selectable.
    public var isExternallyManaged: Bool {
        switch self {
        case .aiAgents, .meetings:
            return true
        case .availability, .pomodoro, .builds, .custom:
            return false
        }
    }
}

public struct QStatePreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var state: QState
    public var scene: QScene
    public var priority: Int

    public init(id: String, name: String, state: QState, scene: QScene, priority: Int) {
        self.id = id
        self.name = name
        self.state = state
        self.scene = scene
        self.priority = priority
    }
}

public struct QModePreset: Codable, Equatable, Identifiable, Sendable {
    public var id: QMode
    public var states: [QStatePreset]
    public var defaultStateID: String
    public var buttonMapping: QButtonMapping
    public var contextualButtonRules: [QContextualButtonRule]
    public var supportsMultiSource: Bool

    public init(
        id: QMode,
        states: [QStatePreset],
        defaultStateID: String,
        buttonMapping: QButtonMapping,
        contextualButtonRules: [QContextualButtonRule] = [],
        supportsMultiSource: Bool = false
    ) {
        self.id = id
        self.states = states
        self.defaultStateID = defaultStateID
        self.buttonMapping = buttonMapping
        self.contextualButtonRules = contextualButtonRules
        self.supportsMultiSource = supportsMultiSource
    }

    public var defaultState: QStatePreset? {
        states.first { $0.id == defaultStateID }
    }

    public func buttonMapping(for state: QState) -> QButtonMapping {
        contextualButtonRules.first { $0.state == state }?.mapping ?? buttonMapping
    }
}

public enum QModeCatalog {
    /// App-level factory defaults. Persistence can replace any preset without
    /// changing the device protocol or firmware behavior.
    public static let presets: [QModePreset] = [
        aiAgents,
        availability,
        meetings,
        pomodoro,
        builds,
        custom
    ]

    public static func preset(for mode: QMode) -> QModePreset {
        presets.first { $0.id == mode } ?? custom
    }

    private static func all(
        _ color: QColor,
        brightness: Double = 0.85,
        animation: QAnimation = .solid,
        speed: Double = 1
    ) -> [QLEDState] {
        Array(
            repeating: QLEDState(
                color: color,
                brightness: brightness,
                animation: animation,
                animationSpeed: speed
            ),
            count: QScene.ledCount
        )
    }

    public static let aiAgents = QModePreset(
        id: .aiAgents,
        states: [
            QStatePreset(
                id: "idle",
                name: "Idle",
                state: .idle,
                scene: QScene(name: "Agent Idle", leds: all(.green, animation: .chaseUp, speed: 0.65)),
                priority: 0
            ),
            QStatePreset(
                id: "working",
                name: "Working",
                state: .working,
                scene: QScene(name: "Agent Working", leds: all(.amber, animation: .chaseUp, speed: 0.9)),
                priority: 50
            ),
            QStatePreset(
                id: "multiple-agents",
                name: "Multiple Agents",
                state: .custom("multipleAgents"),
                scene: QScene(
                    name: "Multiple Agents",
                    leds: [
                        QLEDState(color: .amber, brightness: 0.8),
                        QLEDState(color: .blue, brightness: 0.85, animation: .fadeInOut),
                        QLEDState(color: .green, brightness: 0.8)
                    ]
                ),
                priority: 90
            ),
            QStatePreset(
                id: "needs-input",
                name: "Needs You",
                state: .waitingForUser,
                scene: QScene(name: "Needs You", leds: all(.blue, animation: .fadeInOut, speed: 0.8)),
                priority: 90
            ),
            QStatePreset(
                id: "done",
                name: "Done",
                state: .done,
                scene: QScene(name: "Done", leds: all(.green, animation: .flashThenSolid)),
                priority: 30
            ),
            QStatePreset(
                id: "error",
                name: "Error",
                state: .error,
                scene: QScene(name: "Agent Error", leds: all(.red, animation: .blink, speed: 1.4)),
                priority: 85
            )
        ],
        defaultStateID: "idle",
        buttonMapping: QButtonMapping(singlePress: .focusSource),
        contextualButtonRules: [
            QContextualButtonRule(state: .idle, mapping: QButtonMapping(singlePress: .focusSource)),
            QContextualButtonRule(state: .working, mapping: QButtonMapping(singlePress: .focusSource)),
            QContextualButtonRule(state: .custom("multipleAgents"), mapping: QButtonMapping(singlePress: .focusHighestPrioritySource)),
            QContextualButtonRule(
                state: .waitingForUser,
                mapping: QButtonMapping(singlePress: .focusSource)
            ),
            QContextualButtonRule(state: .done, mapping: QButtonMapping(singlePress: .openResult)),
            QContextualButtonRule(state: .error, mapping: QButtonMapping(singlePress: .focusFailedSource))
        ],
        supportsMultiSource: true
    )

    public static let availability = QModePreset(
        id: .availability,
        states: [
            QStatePreset(id: "available", name: "Available", state: .available, scene: QScene(name: "Available", leds: all(.green)), priority: 10),
            QStatePreset(id: "focus", name: "Focus", state: .focus, scene: QScene(name: "Focus", leds: all(.blue)), priority: 60),
            QStatePreset(id: "busy", name: "Busy / DND", state: .busy, scene: QScene(name: "Busy / DND", leds: all(.red)), priority: 70),
            QStatePreset(
                id: "away",
                name: "Away",
                state: .away,
                scene: QScene(name: "Away", leds: all(.amber, animation: .chaseUp, speed: 0.65)),
                priority: 10
            ),
            QStatePreset(id: "offline", name: "Offline", state: .offline, scene: .idle, priority: 0)
        ],
        defaultStateID: "available",
        buttonMapping: QButtonMapping(singlePress: .cycleScene),
        contextualButtonRules: [
            QContextualButtonRule(state: .available, mapping: QButtonMapping(singlePress: .cycleScene)),
            QContextualButtonRule(state: .focus, mapping: QButtonMapping(singlePress: .cycleScene)),
            QContextualButtonRule(state: .busy, mapping: QButtonMapping(singlePress: .cycleScene)),
            QContextualButtonRule(state: .away, mapping: QButtonMapping(singlePress: .setState(.available))),
            QContextualButtonRule(state: .offline, mapping: QButtonMapping(singlePress: .setState(.available)))
        ]
    )

    public static let meetings = QModePreset(
        id: .meetings,
        states: [
            QStatePreset(id: "free", name: "Free", state: .available, scene: QScene(name: "Free", leds: all(.green)), priority: 10),
            QStatePreset(id: "meeting", name: "In Meeting", state: .meeting, scene: QScene(name: "In Meeting", leds: all(.blue)), priority: 70),
            QStatePreset(
                id: "muted",
                name: "Muted",
                state: .muted,
                scene: QScene(name: "Muted", leds: all(.blue, animation: .fadeInOut, speed: 0.8)),
                priority: 70
            )
        ],
        defaultStateID: "free",
        buttonMapping: QButtonMapping(singlePress: .focusMeetingApplication),
        contextualButtonRules: [
            QContextualButtonRule(state: .available, mapping: QButtonMapping(singlePress: .focusMeetingApplication)),
            QContextualButtonRule(state: .meeting, mapping: QButtonMapping(singlePress: .toggleMeetingMute)),
            QContextualButtonRule(state: .muted, mapping: QButtonMapping(singlePress: .toggleMeetingMute))
        ]
    )

    public static let pomodoro = QModePreset(
        id: .pomodoro,
        states: [
            QStatePreset(id: "idle", name: "Idle", state: .idle, scene: .idle, priority: 0),
            QStatePreset(
                id: "focus",
                name: "Focus",
                state: .pomodoroFocus,
                scene: QScene(name: "Pomodoro Focus", leds: all(.purple, animation: .pulse, speed: 0.55)),
                priority: 60
            ),
            QStatePreset(id: "break", name: "Break", state: .pomodoroBreak, scene: QScene(name: "Pomodoro Break", leds: all(.green)), priority: 60),
            QStatePreset(id: "paused", name: "Paused", state: .paused, scene: QScene(name: "Pomodoro Paused", leds: all(.amber)), priority: 60),
            QStatePreset(
                id: "finished",
                name: "Finished",
                state: .finished,
                scene: QScene(name: "Pomodoro Finished", leds: all(.green, animation: .flash, speed: 1.8)),
                priority: 30
            )
        ],
        defaultStateID: "idle",
        buttonMapping: QButtonMapping(singlePress: .startPomodoro),
        contextualButtonRules: [
            QContextualButtonRule(state: .idle, mapping: QButtonMapping(singlePress: .startPomodoro)),
            QContextualButtonRule(state: .pomodoroFocus, mapping: QButtonMapping(singlePress: .togglePomodoro)),
            QContextualButtonRule(state: .paused, mapping: QButtonMapping(singlePress: .togglePomodoro)),
            QContextualButtonRule(state: .pomodoroBreak, mapping: QButtonMapping(singlePress: .skipPomodoro)),
            QContextualButtonRule(state: .finished, mapping: QButtonMapping(singlePress: .startPomodoro))
        ]
    )

    public static let builds = QModePreset(
        id: .builds,
        states: [
            QStatePreset(id: "idle", name: "Idle", state: .idle, scene: .idle, priority: 0),
            QStatePreset(id: "building", name: "Building", state: .building, scene: QScene(name: "Building", leds: all(.amber, animation: .chaseDown)), priority: 40),
            QStatePreset(id: "testing", name: "Testing", state: .testing, scene: QScene(name: "Testing", leds: all(.blue, animation: .chaseDown)), priority: 40),
            QStatePreset(id: "passed", name: "Passed", state: .passed, scene: QScene(name: "Build Passed", leds: all(.green)), priority: 30),
            QStatePreset(id: "failed", name: "Failed", state: .failed, scene: QScene(name: "Build Failed", leds: all(.red)), priority: 85),
            QStatePreset(id: "deploying", name: "Deploying", state: .deploying, scene: QScene(name: "Deploying", leds: all(.purple, animation: .pulse)), priority: 40),
            QStatePreset(id: "deployed", name: "Deployed", state: .deployed, scene: QScene(name: "Deployed", leds: all(.green, animation: .flash)), priority: 30)
        ],
        defaultStateID: "idle",
        buttonMapping: QButtonMapping(singlePress: .openBuild),
        contextualButtonRules: [
            QContextualButtonRule(state: .failed, mapping: QButtonMapping(singlePress: .openBuild))
        ]
    )

    public static let custom = QModePreset(
        id: .custom,
        states: [
            QStatePreset(id: "off", name: "Off", state: .custom("off"), scene: .idle, priority: 0)
        ],
        defaultStateID: "off",
        buttonMapping: QButtonMapping()
    )
}
