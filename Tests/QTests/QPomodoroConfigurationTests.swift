import Foundation
import Testing
@testable import QCore

@Suite("Pomodoro configuration")
struct QPomodoroConfigurationTests {
    @Test func breaksUseTheSameThirdsWithGreenLights() {
        for remaining in [300, 199, 99, 0] {
            let focus = QPomodoroProgress.scene(remainingSeconds: remaining, totalSeconds: 300)
            let rest = QPomodoroProgress.scene(
                remainingSeconds: remaining, totalSeconds: 300, isBreak: true
            )
            #expect(rest.leds.map(\.isEnabled) == focus.leds.map(\.isEnabled))
            #expect(rest.leds.allSatisfy { $0.color == .green && $0.animation == .solid })
            // Off lights retain their hue for a smooth fade into the opal base.
            #expect(focus.leds.allSatisfy { $0.color == .purple })
        }
    }

    @Test func currentThirdDimsContinuouslyWithoutDisappearingEarly() {
        let levels = QPomodoroProgress.brightnessLevels(
            remainingSeconds: 250,
            totalSeconds: 300
        )
        #expect(levels[0] == 0.85)
        #expect(levels[1] == 0.85)
        #expect(abs(levels[2] - (0.85 * sqrt(0.5))) < 0.000_001)

        let middle = QPomodoroProgress.brightnessLevels(
            remainingSeconds: 150,
            totalSeconds: 300
        )
        #expect(middle[0] == 0.85)
        #expect(abs(middle[1] - (0.85 * sqrt(0.5))) < 0.000_001)
        #expect(middle[2] == 0)

        // Even with 75% of the current third consumed, the LED remains clearly
        // visible instead of looking off before the boundary.
        let nearEnd = QPomodoroProgress.brightnessLevels(
            remainingSeconds: 25,
            totalSeconds: 300
        )
        #expect(abs(nearEnd[0] - 0.425) < 0.000_001)
    }

    @Test func editingDurationPreservesElapsedFocusTime() {
        // Five minutes into 25: shortening to 15 leaves ten minutes.
        let shortened = QPomodoroProgress.adjustedRemaining(
            oldTotal: 1500, remaining: 1200, newTotal: 900
        )
        #expect(shortened == 600)
        // Repeated edits preserve the same elapsed time, including while paused.
        #expect(QPomodoroProgress.adjustedRemaining(
            oldTotal: 900, remaining: shortened, newTotal: 1800
        ) == 1500)
        #expect(QPomodoroProgress.adjustedRemaining(
            oldTotal: 1500, remaining: 300, newTotal: 900
        ) == 0)
        #expect(QPomodoroProgress.adjustedRemaining(
            oldTotal: 300, remaining: 180, newTotal: 600
        ) == 480)
    }

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

    @Test func focusProgressUsesThreeSolidPurpleThirds() {
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 300, totalSeconds: 300) == 3)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 200, totalSeconds: 300) == 3)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 199, totalSeconds: 300) == 2)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 100, totalSeconds: 300) == 2)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 99, totalSeconds: 300) == 1)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 1, totalSeconds: 300) == 1)
        #expect(QPomodoroProgress.litLEDCount(remainingSeconds: 0, totalSeconds: 300) == 0)

        let scene = QPomodoroProgress.scene(remainingSeconds: 199, totalSeconds: 300)
        #expect(scene.leds.map(\.isEnabled) == [true, true, false])
        #expect(scene.leds.prefix(2).allSatisfy { $0.color == .purple })
        #expect(scene.leds.allSatisfy { $0.animation == .solid })
    }
}
