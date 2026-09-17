import Foundation
import Testing
@testable import QCore

struct QMeetingHoldLifecycleTests {
    @Test func duplicateLongPressCannotReplaceActiveTarget() throws {
        var lifecycle = QMeetingHoldLifecycle()
        let started = lifecycle.begin(provider: .discord)
        let first = try #require(started)
        let duplicate = lifecycle.begin(provider: .teams)
        #expect(duplicate == nil)
        #expect(lifecycle.isCurrent(first))
    }

    @Test func releaseInvalidatesQueuedUnmuteAndKeepsOriginalProvider() throws {
        var lifecycle = QMeetingHoldLifecycle()
        let started = lifecycle.begin(provider: .zoom)
        let hold = try #require(started)
        let ended = lifecycle.end()
        let released = try #require(ended)

        #expect(released.provider == .zoom)
        #expect(!lifecycle.isCurrent(hold))
        let repeatedRelease = lifecycle.end()
        #expect(repeatedRelease == nil)
    }
}
