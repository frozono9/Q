import Foundation
import Testing
@testable import QCore

struct QMeetingHoldLifecycleTests {
    @Test func duplicateLongPressCannotReplaceActiveTarget() throws {
        var lifecycle = QMeetingHoldLifecycle()
        let first = try #require(lifecycle.begin(provider: .discord))
        #expect(lifecycle.begin(provider: .teams) == nil)
        #expect(lifecycle.isCurrent(first))
    }

    @Test func releaseInvalidatesQueuedUnmuteAndKeepsOriginalProvider() throws {
        var lifecycle = QMeetingHoldLifecycle()
        let hold = try #require(lifecycle.begin(provider: .zoom))
        let released = try #require(lifecycle.end())

        #expect(released.provider == .zoom)
        #expect(!lifecycle.isCurrent(hold))
        #expect(lifecycle.end() == nil)
    }
}
