import Testing
@testable import QCore

struct QContextualHoldTests {
    @Test func agentModeKeepsDictationEvenDuringACall() {
        for provider in QMeetingProvider.allCases {
            for state: QState in [.meeting, .muted] {
                let meeting = QMeetingSession(provider: provider, state: state, isAvailable: true, canControl: true)
                #expect(QContextualHold.resolve(mode: .aiAgents, meeting: meeting) == .dictation)
                #expect(QContextualHold.resolve(mode: .meetings, meeting: meeting) == .meeting(provider))
            }
        }
    }

    @Test func openAppWithoutCallDoesNotBecomeMicrophoneTarget() {
        let idle = QMeetingSession(provider: .teams, state: .available, isAvailable: true, canControl: true)
        #expect(QContextualHold.resolve(mode: .meetings, meeting: idle) == .none)
        #expect(QContextualHold.resolve(mode: .aiAgents, meeting: nil) == .dictation)
    }
}
