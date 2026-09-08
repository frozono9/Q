import Foundation
import Testing
@testable import QCore

@Suite("Codex activity state resolver")
struct QCodexActivityResolverTests {
    @Test func mapsAnActiveTurnToWorking() {
        #expect(resolve([.started]) == .working)
    }

    @Test func aPendingApprovalTakesPrecedenceOverEarlierWork() {
        #expect(resolve([.started, .needsUser]) == .waitingForUser)
    }

    @Test func resumingAfterInputReturnsToWorking() {
        #expect(resolve([.started, .needsUser, .resumed]) == .working)
    }

    @Test func mapsTerminalEvents() {
        #expect(resolve([.started, .completed]) == .done)
        #expect(resolve([.started, .failed]) == .error)
    }

    private func resolve(_ kinds: [QCodexActivityKind]) -> QState? {
        let base = Date(timeIntervalSince1970: 1_000)
        return QCodexActivityResolver.state(
            for: kinds.enumerated().map {
                QCodexActivityEvent(kind: $0.element, date: base.addingTimeInterval(Double($0.offset)))
            }
        )
    }
}
