import Testing
@testable import QCore

struct QDiagnosticTimelineTests {
    @Test func newestEventsComeFirstAndCapacityIsBounded() {
        var timeline = QDiagnosticTimeline(capacity: 2)
        timeline.append(QDiagnosticEvent(category: "button", title: "one"))
        timeline.append(QDiagnosticEvent(category: "button", title: "two"))
        timeline.append(QDiagnosticEvent(category: "button", title: "three"))

        #expect(timeline.events.map(\.title) == ["three", "two"])
    }
}
