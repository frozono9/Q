import Foundation
import QCore

@main
enum QCoreReliabilityCheck {
    static func main() {
        var timeline = QDiagnosticTimeline(capacity: 2)
        timeline.append(QDiagnosticEvent(category: "test", title: "one"))
        timeline.append(QDiagnosticEvent(category: "test", title: "two"))
        timeline.append(QDiagnosticEvent(category: "test", title: "three"))
        precondition(timeline.events.map(\.title) == ["three", "two"])

        var hold = QMeetingHoldLifecycle()
        let first = hold.begin(provider: .discord)!
        precondition(hold.begin(provider: .teams) == nil)
        precondition(hold.isCurrent(first))
        precondition(hold.end()?.provider == .discord)
        precondition(!hold.isCurrent(first))

        let now = Date()
        let codex = QAgentSession(
            id: "codex",
            source: "Codex",
            displayName: "Project",
            state: .working,
            updatedAt: now
        )
        let claude = QAgentSession(
            id: "claude",
            source: "Claude Code",
            displayName: "Project",
            state: .permissionRequired,
            updatedAt: now.addingTimeInterval(1)
        )
        let slots = QAgentSlotResolver.resolve([codex, claude])
        precondition(slots.count == 2)
        precondition(slots[0].session.source == "Claude Code")
        precondition(slots[1].session.source == "Codex")
        precondition(QAgentSlotResolver.scene(for: slots).leds[0].color == .blue)
        precondition(QAgentSlotResolver.scene(for: slots).leds[1].color == .amber)

        print("QCore reliability checks passed")
    }
}
