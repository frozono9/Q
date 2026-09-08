import Foundation

public struct QAgentSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var displayName: String
    public var state: QState
    public var context: [String: String]
    public var updatedAt: Date

    public init(
        id: String,
        source: String,
        displayName: String,
        state: QState,
        context: [String: String] = [:],
        updatedAt: Date = .now
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.state = state
        self.context = context
        self.updatedAt = updatedAt
    }

    public var relevancePriority: Int {
        switch state {
        case .waitingForUser, .permissionRequired: 5
        case .error, .failed: 4
        case .working: 3
        case .done: 2
        case .idle: 1
        default: 0
        }
    }

    public var ledState: QLEDState {
        switch state {
        case .waitingForUser, .permissionRequired:
            QLEDState(color: .blue, brightness: 0.9, animation: .fadeInOut, animationSpeed: 0.8)
        case .error, .failed:
            QLEDState(color: .red, brightness: 0.9, animation: .blink, animationSpeed: 1.4)
        case .working:
            QLEDState(color: .amber, brightness: 0.8)
        case .done:
            QLEDState(color: .green, brightness: 0.8)
        default:
            .off
        }
    }
}

public struct QAgentSlot: Codable, Equatable, Identifiable, Sendable {
    public var index: Int
    public var session: QAgentSession

    public var id: Int { index }

    public init(index: Int, session: QAgentSession) {
        self.index = index
        self.session = session
    }
}

public enum QAgentSlotResolver {
    public static func resolve(_ sessions: [QAgentSession]) -> [QAgentSlot] {
        sessions
            .sorted {
                if $0.relevancePriority == $1.relevancePriority {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.relevancePriority > $1.relevancePriority
            }
            .prefix(QScene.ledCount)
            .enumerated()
            .map { QAgentSlot(index: $0.offset, session: $0.element) }
    }

    public static func scene(for slots: [QAgentSlot]) -> QScene {
        var leds = Array(repeating: QLEDState.off, count: QScene.ledCount)
        for slot in slots where leds.indices.contains(slot.index) {
            leds[slot.index] = slot.session.ledState
        }
        return QScene(name: "Multiple Agents", leds: leds)
    }
}
