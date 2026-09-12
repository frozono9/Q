import Foundation
import Testing
@testable import QCore

@Suite("Custom modes")
struct QCustomModeTests {
    @Test func draftStartsWithOneValidThreeLEDState() {
        let mode = QCustomModeDefinition.draft()

        #expect(mode.states.count == 1)
        #expect(mode.states[0].scene.leds.count == QScene.ledCount)
        #expect(mode.defaultStateID == mode.states[0].id)
        #expect(mode.isIncludedInCycle)
    }

    @Test func emptyDefinitionsAreNormalizedToAUsableState() {
        let mode = QCustomModeDefinition(name: "Empty", states: [])

        #expect(mode.states.count == 1)
        #expect(mode.defaultStateID == mode.states[0].id)
    }

    @Test func buttonMappingsResolveEveryPhysicalGesture() {
        let mapping = QCustomButtonMapping(
            singlePress: QCustomAction(kind: .nextState),
            doublePress: QCustomAction(kind: .openURL, value: "https://example.com"),
            longPress: QCustomAction(kind: .runShortcut, value: "Focus")
        )

        #expect(mapping.action(for: .singlePress).kind == .nextState)
        #expect(mapping.action(for: .doublePress).value == "https://example.com")
        #expect(mapping.action(for: .longPress).value == "Focus")
    }

    @Test func unspecifiedGesturesInheritTheGeneralButtonSetting() {
        let mapping = QCustomButtonMapping()

        #expect(mapping.singlePress.kind == .nextState)
        #expect(mapping.doublePress.kind == .inheritGlobal)
        #expect(mapping.longPress.kind == .inheritGlobal)
    }

    @Test func profileRoundTripsThroughItsDeclarativeFormat() throws {
        let original = QCustomModeDefinition.draft()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QCustomModeDefinition.self, from: data)

        #expect(decoded == original)
    }
}
