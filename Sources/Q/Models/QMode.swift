import Foundation

public enum QMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case aiAgents
    case availability
    case meetings
    case pomodoro
    case builds
    case custom

    public var id: String { rawValue }

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
}

public enum QModeCatalog {
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
            QStatePreset(id: "idle", name: "Idle", state: .idle, scene: .idle, priority: 0),
            QStatePreset(id: "working", name: "Working", state: .working, scene: .working, priority: 50),
            QStatePreset(
                id: "needs-input",
                name: "Needs Input",
                state: .waitingForUser,
                scene: QScene(
                    name: "Needs Input",
                    leds: [
                        QLEDState(color: .blue, brightness: 0.75),
                        QLEDState(color: .blue, brightness: 0.9, animation: .pulse),
                        QLEDState(color: .blue, brightness: 0.75)
                    ]
                ),
                priority: 90
            ),
            QStatePreset(
                id: "permission",
                name: "Permission",
                state: .permissionRequired,
                scene: QScene(name: "Permission Required", leds: all(.blue, animation: .pulse, speed: 2.2)),
                priority: 95
            ),
            QStatePreset(
                id: "done",
                name: "Done",
                state: .done,
                scene: QScene(name: "Done", leds: all(.green)),
                priority: 30
            ),
            QStatePreset(
                id: "error",
                name: "Error",
                state: .error,
                scene: QScene(
                    name: "Agent Error",
                    leds: [
                        QLEDState(color: .red),
                        QLEDState(color: .red, animation: .blink, animationSpeed: 1.4),
                        QLEDState(color: .red)
                    ]
                ),
                priority: 85
            )
        ],
        defaultStateID: "idle",
        buttonMapping: QButtonMapping(singlePress: .focusSource, doublePress: .cycleActiveSources),
        contextualButtonRules: [
            QContextualButtonRule(
                state: .waitingForUser,
                mapping: QButtonMapping(singlePress: .focusSource, doublePress: .cycleActiveSources)
            ),
            QContextualButtonRule(
                state: .permissionRequired,
                mapping: QButtonMapping(singlePress: .focusSource)
            )
        ],
        supportsMultiSource: true
    )

    public static let availability = QModePreset(
        id: .availability,
        states: [
            QStatePreset(id: "available", name: "Available", state: .available, scene: QScene(name: "Available", leds: all(.green)), priority: 10),
            QStatePreset(id: "focus", name: "Focused", state: .focus, scene: QScene(name: "Focused", leds: all(.amber)), priority: 60),
            QStatePreset(id: "busy", name: "Busy", state: .busy, scene: QScene(name: "Busy", leds: all(.red)), priority: 70),
            QStatePreset(
                id: "away",
                name: "Away",
                state: .away,
                scene: QScene(name: "Away", leds: [QLEDState(color: .amber), .off, .off]),
                priority: 10
            ),
            QStatePreset(id: "offline", name: "Offline", state: .offline, scene: .idle, priority: 0)
        ],
        defaultStateID: "available",
        buttonMapping: QButtonMapping(singlePress: .cycleScene, doublePress: .toggleAutomaticManual, longPress: .turnOff)
    )

    public static let meetings = QModePreset(
        id: .meetings,
        states: [
            QStatePreset(id: "free", name: "Free", state: .available, scene: QScene(name: "Free", leds: all(.green)), priority: 10),
            QStatePreset(id: "meeting", name: "In Meeting", state: .meeting, scene: QScene(name: "In Meeting", leds: all(.blue)), priority: 70),
            QStatePreset(id: "muted", name: "Muted", state: .muted, scene: QScene(name: "Muted", leds: all(.amber)), priority: 70),
            QStatePreset(id: "presenting", name: "Presenting", state: .presenting, scene: QScene(name: "Presenting", leds: all(.purple)), priority: 80),
            QStatePreset(
                id: "recording",
                name: "Recording",
                state: .recording,
                scene: QScene(name: "Recording", leds: all(.red, animation: .pulse, speed: 1.2)),
                priority: 80
            )
        ],
        defaultStateID: "free",
        buttonMapping: QButtonMapping(singlePress: .toggleMeetingMute, doublePress: .raiseHand, longPress: .focusMeetingApplication),
        contextualButtonRules: [
            QContextualButtonRule(state: .meeting, mapping: QButtonMapping(singlePress: .toggleMeetingMute, doublePress: .raiseHand))
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
        buttonMapping: QButtonMapping(singlePress: .togglePomodoro, doublePress: .skipPomodoro, longPress: .cancelPomodoro),
        contextualButtonRules: [
            QContextualButtonRule(state: .pomodoroFocus, mapping: QButtonMapping(singlePress: .togglePomodoro, doublePress: .skipPomodoro, longPress: .cancelPomodoro)),
            QContextualButtonRule(state: .pomodoroBreak, mapping: QButtonMapping(singlePress: .togglePomodoro, doublePress: .skipPomodoro, longPress: .cancelPomodoro))
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
        buttonMapping: QButtonMapping(singlePress: .openBuild, doublePress: .retryBuild),
        contextualButtonRules: [
            QContextualButtonRule(state: .failed, mapping: QButtonMapping(singlePress: .openBuild, doublePress: .retryBuild))
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
