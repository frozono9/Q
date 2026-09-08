import Testing
@testable import QCore

@Suite("Discord RTC log parser")
struct QDiscordRTCLogParserTests {
    @Test func detectsPrimaryVoiceConnection() {
        let line = "[info] [RTCConnection(123, default)] RTC connection state: RTC_CONNECTING => RTC_CONNECTED"
        #expect(QDiscordRTCLogParser.state(from: line) == .meeting)
    }

    @Test func detectsLeavingVoice() {
        let line = "[info] [RTCConnection(123, default)] RTC connection state: RTC_CONNECTED => RTC_DISCONNECTED"
        #expect(QDiscordRTCLogParser.state(from: line) == .available)
    }

    @Test func ignoresScreenShareConnections() {
        let line = "[info] [RTCConnection(123, stream)] RTC connection state: RTC_CONNECTING => RTC_CONNECTED"
        #expect(QDiscordRTCLogParser.state(from: line) == nil)
    }

    @Test func ignoresIntermediateConnectionStates() {
        let line = "[info] [RTCConnection(123, default)] RTC connection state: CONNECTING => AUTHENTICATING"
        #expect(QDiscordRTCLogParser.state(from: line) == nil)
    }
}
