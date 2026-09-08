import Testing
@testable import QCore

@Suite("Pomodoro configuration")
struct QPomodoroConfigurationTests {
    @Test func shipsExpectedFocusPresets() {
        #expect(QPomodoroConfiguration.commonFocusDurations == [15, 25, 30, 45, 60, 90])
    }

    @Test func clampsCustomDurationsToSafeLocalBounds() {
        let short = QPomodoroConfiguration(focusMinutes: 0, breakMinutes: 0)
        let long = QPomodoroConfiguration(focusMinutes: 999, breakMinutes: 999)

        #expect(short.focusMinutes == 1)
        #expect(short.breakMinutes == 1)
        #expect(long.focusMinutes == 180)
        #expect(long.breakMinutes == 60)
    }
}
