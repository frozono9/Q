import Testing
@testable import QCore

@Suite("Prepackaged modes")
struct QModeCatalogTests {
    @Test func exposesPrimaryModes() {
        #expect(QMode.primaryModes == [.aiAgents, .availability, .meetings, .pomodoro, .relaxing])
        #expect(!QMode.primaryModes.contains(.builds))
        #expect(!QMode.primaryModes.contains(.custom))
    }

    @Test func integrationOwnedModesDoNotExposeManualStateControl() {
        #expect(QMode.aiAgents.isExternallyManaged)
        #expect(QMode.meetings.isExternallyManaged)
        #expect(!QMode.availability.isExternallyManaged)
        #expect(!QMode.pomodoro.isExternallyManaged)
        #expect(!QMode.relaxing.isExternallyManaged)
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

    @Test func factoryPresetsFollowTheMVPVisualGrammar() throws {
        let agentIdle = try #require(state("idle", in: .aiAgents))
        let agentWorking = try #require(state("working", in: .aiAgents))
        let needsYou = try #require(state("needs-input", in: .aiAgents))
        let done = try #require(state("done", in: .aiAgents))
        let error = try #require(state("error", in: .aiAgents))
        let availabilityFocus = try #require(state("focus", in: .availability))
        let meetingMuted = try #require(state("muted", in: .meetings))
        let relaxing = try #require(state("flow", in: .relaxing))

        expectAllLEDs(agentIdle, color: .green, animation: .chaseUp)
        expectAllLEDs(agentWorking, color: .amber, animation: .chaseUp)
        expectAllLEDs(needsYou, color: .blue, animation: .fadeInOut)
        expectAllLEDs(done, color: .green, animation: .flashThenSolid)
        expectAllLEDs(error, color: .red, animation: .blink)
        expectAllLEDs(availabilityFocus, color: .blue, animation: .solid)
        expectAllLEDs(meetingMuted, color: .blue, animation: .fadeInOut)
        expectAllLEDs(relaxing, color: .white, animation: .rainbow)
        #expect(relaxing.scene.leds.map(\.phaseOffset) == [0.0, 0.09, 0.18])
    }

    @Test func needsYouOutranksWorking() throws {
        let needsYou = try #require(state("needs-input", in: .aiAgents))
        let working = try #require(state("working", in: .aiAgents))

        #expect(needsYou.priority > working.priority)
    }

    @Test func multiAgentRenderingIsExplicitlySupported() {
        #expect(QModeCatalog.aiAgents.supportsMultiSource)
        #expect(!QModeCatalog.availability.supportsMultiSource)
    }

    @Test func factoryMappingsUseOneContextualPress() {
        for mode in QModeCatalog.presets {
            #expect(mode.buttonMapping.doublePress == .none)
            if mode.id == .aiAgents {
                #expect(mode.buttonMapping.longPress == .startCodexDictation)
            } else {
                #expect(mode.buttonMapping.longPress == .none)
            }
            for rule in mode.contextualButtonRules {
                #expect(rule.mapping.doublePress == .none)
                if mode.id == .aiAgents {
                    #expect(rule.mapping.longPress == .startCodexDictation)
                } else {
                    #expect(rule.mapping.longPress == .none)
                }
            }
        }

        #expect(
            QModeCatalog.aiAgents.buttonMapping(for: .waitingForUser).singlePress
                == .focusSource
        )
        #expect(
            QModeCatalog.aiAgents.buttonMapping(for: .idle).singlePress
                == .focusMostRecentCodexChat
        )
        #expect(
            QModeCatalog.availability.buttonMapping(for: .away).singlePress
                == .setState(.available)
        )
        #expect(
            QModeCatalog.pomodoro.buttonMapping(for: .pomodoroBreak).singlePress
                == .skipPomodoro
        )
    }

    private func state(_ id: String, in mode: QMode) -> QStatePreset? {
        QModeCatalog.preset(for: mode).states.first { $0.id == id }
    }

    private func expectAllLEDs(
        _ preset: QStatePreset,
        color: QColor,
        animation: QAnimation
    ) {
        #expect(preset.scene.leds.allSatisfy { $0.color == color })
        #expect(preset.scene.leds.allSatisfy { $0.animation == animation })
    }
}
