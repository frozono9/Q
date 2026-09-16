import Foundation
import Testing
@testable import QCore

@Suite("Q models")
struct QModelTests {
    @Test func hexColorRoundTrip() {
        let color = QColor(hex: "#FF8800")

        #expect(color?.hex == "#FF8800")
    }

    @Test func sceneAlwaysContainsExactlyThreeLEDs() {
        let shortScene = QScene(
            name: "Short",
            leds: [QLEDState(color: .red)]
        )
        let longScene = QScene(
            name: "Long",
            leds: Array(repeating: QLEDState(color: .blue), count: 5)
        )

        #expect(shortScene.leds.count == 3)
        #expect(shortScene.leds[0].color == .red)
        #expect(!shortScene.leds[1].isEnabled)
        #expect(longScene.leds.count == 3)
    }

    @Test func sceneSerializationPreservesAnimationSettings() throws {
        let scene = QScene(
            name: "Animated",
            leds: [
                QLEDState(
                    color: .amber,
                    brightness: 0.7,
                    animation: .pulse,
                    animationSpeed: 1.25,
                    phaseOffset: 0.2
                )
            ]
        )

        let data = try JSONEncoder().encode(scene)
        let decoded = try JSONDecoder().decode(QScene.self, from: data)

        #expect(decoded == scene)
    }

    @Test func gestureSettingsShipWithSafeGeneralDefaults() throws {
        let settings = QGestureSettings()

        #expect(settings.singlePress == .contextual)
        #expect(settings.doublePress == .nextMode)
        #expect(settings.longPress == .contextual)
        #expect(try JSONDecoder().decode(
            QGestureSettings.self,
            from: JSONEncoder().encode(settings)
        ) == settings)
    }
}
