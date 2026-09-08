import Testing
@testable import QCore

@Suite("Prepackaged modes")
struct QModeCatalogTests {
    @Test func shipsTheSixLaunchModes() {
        #expect(QModeCatalog.presets.map(\.id) == QMode.allCases)
    }

    @Test func everyPresetHasAResolvableDefaultAndThreeLEDScenes() {
        for mode in QModeCatalog.presets {
            #expect(mode.defaultState != nil, "\(mode.id) has no default state")
            for state in mode.states {
                #expect(state.scene.leds.count == QScene.ledCount)
                #expect((0...100).contains(state.priority))
            }
        }
    }

    @Test func permissionIsTheHighestPriorityAgentState() {
        let permission = QModeCatalog.aiAgents.states.first { $0.state == .permissionRequired }
        let others = QModeCatalog.aiAgents.states.filter { $0.state != .permissionRequired }

        #expect(permission?.priority == 95)
        #expect(others.allSatisfy { $0.priority < 95 })
    }

    @Test func multiAgentRenderingIsExplicitlySupported() {
        #expect(QModeCatalog.aiAgents.supportsMultiSource)
        #expect(!QModeCatalog.availability.supportsMultiSource)
    }

    @Test func buttonMappingsAreIndependentByTrigger() {
        let mapping = QModeCatalog.pomodoro.buttonMapping

        #expect(mapping.action(for: .singlePress) == .togglePomodoro)
        #expect(mapping.action(for: .doublePress) == .skipPomodoro)
        #expect(mapping.action(for: .longPress) == .cancelPomodoro)
    }
}
