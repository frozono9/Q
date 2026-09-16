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

    public var stableIdentity: String { "\(source)::\(id)" }

    public var ledState: QLEDState {
        switch state {
        case .waitingForUser, .permissionRequired:
            QLEDState(color: .blue, brightness: 0.9, animation: .fadeInOut, animationSpeed: 0.8)
        case .error, .failed:
            QLEDState(color: .red, brightness: 0.9, animation: .blink, animationSpeed: 1.4)
        case .working:
            QLEDState(
                color: .amber,
                brightness: 0.8,
                animation: .fadeInOut,
                animationSpeed: 0.9
            )
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
    public static func resolve(
        _ sessions: [QAgentSession],
        preserving previousSlots: [QAgentSlot] = []
    ) -> [QAgentSlot] {
        let selected = sessions
            .sorted {
                if $0.relevancePriority == $1.relevancePriority {
                    return $0.updatedAt > $1.updatedAt
                }
                return $0.relevancePriority > $1.relevancePriority
            }
            .prefix(QScene.ledCount)
        var selectedByID: [String: QAgentSession] = [:]
        for session in selected where selectedByID[session.stableIdentity] == nil {
            selectedByID[session.stableIdentity] = session
        }
        var assigned: [Int: QAgentSession] = [:]
        var assignedIDs: Set<String> = []

        for slot in previousSlots.sorted(by: { $0.index < $1.index }) {
            guard QScene.ledCount > slot.index,
                  let updated = selectedByID[slot.session.stableIdentity],
                  assigned[slot.index] == nil else { continue }
            assigned[slot.index] = updated
            assignedIDs.insert(updated.stableIdentity)
        }

        var openIndices = (0..<QScene.ledCount).filter { assigned[$0] == nil }
        for session in selected where !assignedIDs.contains(session.stableIdentity) {
            guard !openIndices.isEmpty else { break }
            assigned[openIndices.removeFirst()] = session
            assignedIDs.insert(session.stableIdentity)
        }

        return assigned.keys.sorted().compactMap { index in
            assigned[index].map { QAgentSlot(index: index, session: $0) }
        }
    }

    public static func scene(for slots: [QAgentSlot]) -> QScene {
        var leds = Array(repeating: QLEDState.off, count: QScene.ledCount)
        for slot in slots where leds.indices.contains(slot.index) {
            leds[slot.index] = slot.session.ledState
        }
        return QScene(name: "Multiple Agents", leds: leds)
    }
}
