import Foundation
import Testing
@testable import QCore

@Suite("Agent LED slots")
struct QAgentSlotResolverTests {
    @Test func choosesTheThreeMostRelevantAgentsInPriorityOrder() {
        let sessions = [
            session("idle", .idle, secondsAgo: 1),
            session("done", .done, secondsAgo: 2),
            session("working", .working, secondsAgo: 3),
            session("error", .error, secondsAgo: 4),
            session("needs", .waitingForUser, secondsAgo: 5)
        ]

        let slots = QAgentSlotResolver.resolve(sessions)

        #expect(slots.map(\.session.id) == ["needs", "error", "working"])
        #expect(slots.map(\.index) == [0, 1, 2])
    }

    @Test func recencyBreaksEqualPriorityTies() {
        let older = session("older", .working, secondsAgo: 30)
        let newer = session("newer", .working, secondsAgo: 2)

        let slots = QAgentSlotResolver.resolve([older, newer])

        #expect(slots.map(\.session.id) == ["newer", "older"])
    }

    @Test func sceneUsesOneIndependentLEDPerAgentAndLeavesUnusedSlotsOff() {
        let slots = QAgentSlotResolver.resolve([
            session("needs", .waitingForUser),
            session("working", .working)
        ])

        let scene = QAgentSlotResolver.scene(for: slots)

        #expect(scene.leds[0].color == .blue)
        #expect(scene.leds[1].color == .amber)
        #expect(!scene.leds[2].isEnabled)
    }

    private func session(
        _ id: String,
        _ state: QState,
        secondsAgo: TimeInterval = 0
    ) -> QAgentSession {
        QAgentSession(
            id: id,
            source: "test",
            displayName: id,
            state: state,
            updatedAt: Date.now.addingTimeInterval(-secondsAgo)
        )
    }
}
