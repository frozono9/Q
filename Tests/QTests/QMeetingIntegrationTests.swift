import Foundation
import Testing
@testable import QCore

@Suite("Meeting integrations")
struct QMeetingArbiterTests {
    @Test func activeMeetingOutranksFreeProviders() {
        let sessions = [
            session(.discord, .available, secondsAgo: 0),
            session(.zoom, .meeting, secondsAgo: 20)
        ]
        #expect(QMeetingArbiter.resolve(sessions)?.provider == .zoom)
    }

    @Test func mutedCallOutranksGeneralCall() {
        let sessions = [
            session(.zoom, .meeting, secondsAgo: 0),
            session(.teams, .muted, secondsAgo: 20)
        ]
        #expect(QMeetingArbiter.resolve(sessions)?.provider == .teams)
    }

    @Test func newestCallBreaksEqualStateTies() {
        let sessions = [
            session(.zoom, .meeting, secondsAgo: 20),
            session(.googleMeet, .meeting, secondsAgo: 0)
        ]
        #expect(QMeetingArbiter.resolve(sessions)?.provider == .googleMeet)
    }

    @Test func manualProviderSelectionIgnoresOtherActiveCalls() {
        let sessions = [
            session(.zoom, .muted, secondsAgo: 0),
            session(.teams, .meeting, secondsAgo: 10)
        ]
        #expect(QMeetingArbiter.resolve(sessions, selection: .teams)?.provider == .teams)
    }

    @Test func manualProviderSelectionDoesNotFallThroughToAnotherProvider() {
        let sessions = [
            session(.zoom, .meeting, secondsAgo: 0),
            session(.teams, .available, secondsAgo: 0)
        ]
        #expect(QMeetingArbiter.resolve(sessions, selection: .teams) == nil)
    }

    @Test func accessibilityControlsClassifyMuteStateWithoutFalsePositive() {
        #expect(QMeetingSurfaceClassifier.state(
            buttonLabels: ["Unmute my audio", "Leave meeting"],
            windowTitles: ["Zoom Meeting"],
            kind: .zoom
        ) == .muted)
        #expect(QMeetingSurfaceClassifier.state(
            buttonLabels: ["Mute mic", "Leave"],
            windowTitles: ["Microsoft Teams meeting"],
            kind: .teams
        ) == .meeting)
        #expect(QMeetingSurfaceClassifier.state(
            buttonLabels: ["Mute"],
            windowTitles: ["Zoom Workplace"],
            kind: .zoom
        ) == nil)
    }

    @Test func googleMeetAndSpanishControlsAreRecognized() {
        #expect(QMeetingSurfaceClassifier.state(
            buttonLabels: ["Activar micrófono", "Salir de la llamada"],
            windowTitles: ["Meet - abc-defg-hij - Google Chrome"],
            kind: .googleMeet
        ) == .muted)
    }

    @Test func classifierAndButtonActionsShareTheSameNormalizedVocabulary() {
        let labels = ["Activar micrófono", "Salir de la llamada"]
        #expect(QMeetingControlVocabulary.microphoneState(buttonLabels: labels) == .muted)
        #expect(QMeetingControlVocabulary.buttonPerformsDesiredAction(
            label: "Activar micrófono",
            shouldMute: false
        ))
        #expect(QMeetingControlVocabulary.buttonPerformsDesiredAction(
            label: "Desactivar micrófono",
            shouldMute: true
        ))
    }

    @Test func unrelatedMuteButtonsAreNotClassifiedAsMicrophoneControls() {
        #expect(QMeetingControlVocabulary.microphoneState(
            buttonLabels: ["Mute notifications", "Silenciar notificaciones"]
        ) == .unknown)
    }

    @Test func actionWordsDoNotMatchInsideOppositeActions() {
        for label in ["Desactivar micrófono (Ctrl+M)", "Desactivar audio"] {
            #expect(QMeetingControlVocabulary.microphoneState(buttonLabels: [label]) == .unmuted)
            #expect(!QMeetingControlVocabulary.buttonPerformsDesiredAction(label: label, shouldMute: false))
        }
        for label in ["Activar audio (Ctrl+M)", "Unmute my audio", "Unmute"] {
            #expect(QMeetingControlVocabulary.microphoneState(buttonLabels: [label]) == .muted)
        }
    }

    @Test func persistentMuteToggleUsesItsAccessibilityValue() {
        #expect(QMeetingControlVocabulary.microphoneToggleState(
            label: "Mute",
            isOn: true
        ) == .muted)
        #expect(QMeetingControlVocabulary.microphoneToggleState(
            label: "Mute",
            isOn: false
        ) == .unmuted)
        #expect(QMeetingControlVocabulary.microphoneToggleState(
            label: "Mute notifications",
            isOn: true
        ) == .unknown)
    }

    @Test func opaqueNewTeamsCallWindowIsRecognizedWithoutGuessingFromOrdinaryChat() {
        #expect(QMeetingSurfaceClassifier.hasTeamsMeetingWindow(
            windowTitles: ["Meeting compact view | Alex | Microsoft Teams"]
        ))
        #expect(QMeetingSurfaceClassifier.hasTeamsMeetingWindow(
            windowTitles: ["Project sync meeting | Microsoft Teams"]
        ))
        #expect(QMeetingSurfaceClassifier.hasTeamsMeetingWindow(
            windowTitles: ["Chat | Alex | Microsoft Teams"]
        ) == false)
        #expect(QMeetingSurfaceClassifier.hasTeamsCompactCallWindow(windowLayers: [0, 24]))
        #expect(QMeetingSurfaceClassifier.hasTeamsCompactCallWindow(windowLayers: [0]) == false)
    }

    private func session(
        _ provider: QMeetingProvider,
        _ state: QState,
        secondsAgo: TimeInterval
    ) -> QMeetingSession {
        QMeetingSession(
            provider: provider,
            state: state,
            isAvailable: true,
            canControl: true,
            updatedAt: .now.addingTimeInterval(-secondsAgo)
        )
    }
}
