import Foundation

public enum QDiscordRTCLogParser {
    /// Discord writes one of these lines whenever its primary voice connection changes.
    /// Screen-share connections use `stream` and intentionally do not affect Meeting mode.
    public static func state(from line: String) -> QState? {
        guard line.contains(", default)] RTC connection state:") else { return nil }
        guard let arrow = line.range(of: "=>", options: .backwards) else { return nil }

        let destination = line[arrow.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        switch destination {
        case "RTC_CONNECTED":
            return .meeting
        case "RTC_DISCONNECTED", "DISCONNECTED":
            return .available
        default:
            return nil
        }
    }
}
