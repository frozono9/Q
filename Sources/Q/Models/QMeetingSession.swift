import Foundation

public enum QMeetingProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case discord
    case zoom
    case googleMeet
    case teams

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .discord: "Discord"
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        }
    }
}

public enum QMeetingProviderSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case discord
    case zoom
    case googleMeet
    case teams

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .automatic: "Auto"
        case .discord: "Discord"
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        }
    }

    public var provider: QMeetingProvider? {
        switch self {
        case .automatic: nil
        case .discord: .discord
        case .zoom: .zoom
        case .googleMeet: .googleMeet
        case .teams: .teams
        }
    }
}

public enum QMeetingSurfaceKind: Equatable, Sendable {
    case zoom
    case teams
    case googleMeet
}

public enum QMicrophoneState: String, Codable, Equatable, Sendable {
    case muted
    case unmuted
    case unknown

    public var qState: QState? {
        switch self {
        case .muted: .muted
        case .unmuted: .meeting
        case .unknown: nil
        }
    }
}

public enum QMeetingControlResult: Equatable, Sendable {
    case confirmed(QMicrophoneState)
    case sentUnconfirmed
    case unavailable
    case permissionDenied
    case failed

    public var wasDelivered: Bool {
        switch self {
        case .confirmed, .sentUnconfirmed: true
        case .unavailable, .permissionDenied, .failed: false
        }
    }
}

public enum QMeetingControlVocabulary {
    public static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func microphoneState(buttonLabels: [String]) -> QMicrophoneState {
        for rawLabel in buttonLabels {
            let label = normalized(rawLabel)
            if label == "unmute" || unmuteTerms.contains(where: { label.contains($0) }) {
                return .muted
            }
        }
        for rawLabel in buttonLabels {
            let label = normalized(rawLabel)
            if label == "mute" || label == "silenciar" ||
                muteTerms.contains(where: { label.contains($0) }) {
                return .unmuted
            }
        }
        return .unknown
    }

    public static func buttonPerformsDesiredAction(
        label rawLabel: String,
        shouldMute: Bool
    ) -> Bool {
        let state = microphoneState(buttonLabels: [rawLabel])
        return shouldMute ? state == .unmuted : state == .muted
    }

    /// Electron can expose a persistent toggle named "Mute". Here the label
    /// names the setting rather than the next action, so its AX value is the
    /// authoritative microphone state.
    public static func microphoneToggleState(
        label rawLabel: String,
        isOn: Bool
    ) -> QMicrophoneState {
        guard microphoneState(buttonLabels: [rawLabel]) == .unmuted else {
            return .unknown
        }
        return isOn ? .muted : .unmuted
    }

    public static func hasLeaveControl(buttonLabels: [String]) -> Bool {
        buttonLabels.map(normalized).contains { label in
            leaveTerms.contains(where: { label.contains($0) })
        }
    }

    private static let unmuteTerms = [
        "turn on microphone", "unmute my audio", "activar sonido",
        "activar microfono", "reactivar audio", "activar audio"
    ]
    private static let muteTerms = [
        "mute microphone", "mute mic", "turn off microphone", "mute my audio",
        "silenciar microfono", "silenciar audio", "desactivar microfono", "desactivar audio"
    ]
    private static let leaveTerms = [
        "leave", "leave call", "leave meeting", "hang up", "end call",
        "salir", "abandonar", "finalizar llamada", "colgar"
    ]
}

public enum QMeetingSurfaceClassifier {
    public static func state(
        buttonLabels: [String],
        windowTitles: [String],
        kind: QMeetingSurfaceKind
    ) -> QState? {
        let buttons = buttonLabels.map(QMeetingControlVocabulary.normalized)
        let titles = windowTitles.map(normalized)
        let microphoneState = QMeetingControlVocabulary.microphoneState(buttonLabels: buttons)
        let hasLeave = QMeetingControlVocabulary.hasLeaveControl(buttonLabels: buttons)
        let recognizableWindow: Bool = switch kind {
        case .zoom:
            titles.contains { $0.contains("zoom meeting") || $0.contains("zoom webinar") }
        case .teams:
            titles.contains { $0.contains("microsoft teams meeting") || $0.contains("meeting | microsoft teams") }
        case .googleMeet:
            titles.contains { $0.contains("google meet") || $0.contains("meet -") }
        }
        let hasMeetingIdentity = kind == .googleMeet
            ? recognizableWindow
            : (hasLeave || recognizableWindow)
        guard microphoneState != .unknown, hasMeetingIdentity else { return nil }
        return microphoneState.qState
    }

    /// New Teams renders its call controls inside Edge WebView content that is
    /// intentionally opaque to macOS Accessibility. Its native window title is
    /// still exposed, so use that as the call-presence fallback. Mute state is
    /// deliberately not inferred here; the integration preserves the last
    /// known/optimistic state until the call window disappears.
    public static func hasTeamsMeetingWindow(windowTitles: [String]) -> Bool {
        windowTitles.map(normalized).contains { title in
            title.contains("meeting compact view") ||
                title.contains("meeting | microsoft teams") ||
                title.contains("meeting | microsoft teams classic") ||
                title.contains("call | microsoft teams") ||
                title.contains("reunion | microsoft teams") ||
                title.contains("llamada | microsoft teams") ||
                ((title.contains("meeting") || title.contains("reunion") || title.contains("llamada")) &&
                    title.hasSuffix("| microsoft teams"))
        }
    }

    /// Teams places its always-on-top compact call window at window level 24.
    /// Unlike window names, the owning PID and window level remain available
    /// without Screen Recording permission, making this the preferred fallback.
    public static func hasTeamsCompactCallWindow(windowLayers: [Int]) -> Bool {
        windowLayers.contains(24)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct QMeetingSession: Equatable, Identifiable, Sendable {
    public var provider: QMeetingProvider
    public var state: QState
    public var isAvailable: Bool
    public var canControl: Bool
    public var updatedAt: Date
    public var context: [String: String]

    public var id: String { provider.rawValue }
    public var isActive: Bool { state == .meeting || state == .muted }

    public init(
        provider: QMeetingProvider,
        state: QState,
        isAvailable: Bool,
        canControl: Bool,
        updatedAt: Date = .now,
        context: [String: String] = [:]
    ) {
        self.provider = provider
        self.state = state
        self.isAvailable = isAvailable
        self.canControl = canControl
        self.updatedAt = updatedAt
        self.context = context
    }
}

public enum QMeetingArbiter {
    public static func resolve(
        _ sessions: [QMeetingSession],
        selection: QMeetingProviderSelection = .automatic
    ) -> QMeetingSession? {
        let candidates = if let provider = selection.provider {
            sessions.filter { $0.provider == provider }
        } else {
            sessions
        }
        return candidates
            .filter(\.isActive)
            .sorted {
                let left = statePriority($0.state)
                let right = statePriority($1.state)
                if left == right {
                    if $0.updatedAt == $1.updatedAt {
                        return $0.provider.rawValue < $1.provider.rawValue
                    }
                    return $0.updatedAt > $1.updatedAt
                }
                return left > right
            }
            .first
    }

    private static func statePriority(_ state: QState) -> Int {
        switch state {
        case .muted: 2
        case .meeting: 1
        default: 0
        }
    }
}
