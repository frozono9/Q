import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OSLog
import QCore

@MainActor
final class LocalMeetingIntegration {
    let provider: QMeetingProvider
    private let bundleIdentifiers: [String]
    private let applicationPaths: [String]
    private let detectionKind: QMeetingSurfaceKind
    private let muteKeyCode: CGKeyCode
    private let muteFlags: CGEventFlags
    private let logger: Logger
    private var monitoringTask: Task<Void, Never>?
    private var lastSnapshot: QMeetingSession?
    private var activeApplication: NSRunningApplication?
    private var lastRequestedMicrophoneState: QMicrophoneState?

    init(
        provider: QMeetingProvider,
        bundleIdentifiers: [String],
        applicationPaths: [String],
        detectionKind: QMeetingSurfaceKind,
        muteKeyCode: CGKeyCode,
        muteFlags: CGEventFlags
    ) {
        self.provider = provider
        self.bundleIdentifiers = bundleIdentifiers
        self.applicationPaths = applicationPaths
        self.detectionKind = detectionKind
        self.muteKeyCode = muteKeyCode
        self.muteFlags = muteFlags
        logger = Logger(subsystem: "app.q", category: "\(provider.rawValue)-integration")
    }

    var canControl: Bool { AXIsProcessTrusted() }

    func start(onUpdate: @escaping @MainActor @Sendable (QMeetingSession) -> Void) {
        guard monitoringTask == nil else { return }
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                var snapshot = await inspect()
                if let previous = lastSnapshot,
                   previous.provider == snapshot.provider,
                   previous.state == snapshot.state,
                   previous.isAvailable == snapshot.isAvailable,
                   previous.canControl == snapshot.canControl,
                   previous.context == snapshot.context {
                    snapshot.updatedAt = previous.updatedAt
                }
                if snapshot != lastSnapshot {
                    lastSnapshot = snapshot
                    onUpdate(snapshot)
                    logger.notice(
                        "\(provider.name, privacy: .public) available=\(snapshot.isAvailable) state=\(String(describing: snapshot.state), privacy: .public)"
                    )
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func focus() {
        if let activeApplication {
            let processIdentifier = activeApplication.processIdentifier
            let kind = detectionKind
            Task { @MainActor in
                _ = await Task.detached(priority: .userInitiated) {
                    QMeetingAccessibilitySurface.raiseMeetingWindow(
                        processIdentifier: processIdentifier,
                        kind: kind
                    )
                }.value
                activeApplication.activate(options: [.activateAllWindows])
            }
            return
        }
        guard let path = applicationPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error {
                self.logger.error("Could not open \(self.provider.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func toggleMute() async -> QMeetingControlResult {
        let freshState = await observedMicrophoneState()
        let currentState = if freshState != .unknown {
            freshState
        } else if let lastRequestedMicrophoneState {
            lastRequestedMicrophoneState
        } else {
            Self.microphoneState(from: lastSnapshot?.state)
        }
        guard currentState != .unknown else { return .failed }
        return await setMuted(currentState == .unmuted)
    }

    /// Sets, rather than toggles, the microphone state. This is used for
    /// push-to-talk so a missed/repeated button event cannot invert the result.
    func setMuted(_ shouldMute: Bool) async -> QMeetingControlResult {
        let applications = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        guard let application = activeApplication ?? applications.first else {
            focus()
            return .unavailable
        }
        guard canControl else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return .permissionDenied
        }

        activeApplication = application
        let processIdentifiers = relatedProcessIdentifiers(for: applications)
        let desired: QMicrophoneState = shouldMute ? .muted : .unmuted
        let before = await observedMicrophoneState(in: processIdentifiers)
        logger.notice(
            "Control requested desired=\(desired.rawValue, privacy: .public) observed=\(before.rawValue, privacy: .public) active=\(self.lastSnapshot?.isActive == true)"
        )
        if before == desired {
            lastRequestedMicrophoneState = desired
            return .confirmed(desired)
        }

        let pressed = await Task.detached(priority: .userInitiated) { [detectionKind] in
            for processIdentifier in processIdentifiers {
                if QMeetingAccessibilitySurface.pressMicrophoneButton(
                    processIdentifier: processIdentifier,
                    shouldMute: shouldMute,
                    kind: detectionKind
                ) {
                    return true
                }
            }
            return false
        }.value
        if pressed {
            let confirmation = await confirmMicrophoneState(desired, in: processIdentifiers)
            let result: QMeetingControlResult = confirmation == .failed
                ? .sentUnconfirmed
                : confirmation
            if result.wasDelivered { lastRequestedMicrophoneState = desired }
            return result
        }

        guard before != .unknown || lastSnapshot?.isActive == true else {
            return .unavailable
        }
        guard await focusCallSurface(
            application: application,
            processIdentifiers: processIdentifiers
        ) else {
            logger.error("Could not focus \(self.provider.name, privacy: .public) before keyboard fallback")
            return .failed
        }
        guard Self.postKeyboardShortcut(keyCode: muteKeyCode, flags: muteFlags) else {
            return .failed
        }
        logger.notice("Delivered keyboard fallback to \(self.provider.name, privacy: .public)")
        let confirmation = await confirmMicrophoneState(desired, in: processIdentifiers)
        let result: QMeetingControlResult = confirmation == .failed
            ? .sentUnconfirmed
            : confirmation
        if result.wasDelivered { lastRequestedMicrophoneState = desired }
        return result
    }

    private func observedMicrophoneState() async -> QMicrophoneState {
        let applications = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        return await observedMicrophoneState(in: relatedProcessIdentifiers(for: applications))
    }

    private func observedMicrophoneState(in processIdentifiers: [pid_t]) async -> QMicrophoneState {
        let kind = detectionKind
        return await Task.detached(priority: .utility) {
            for processIdentifier in processIdentifiers {
                let surface = QMeetingAccessibilitySurface(processIdentifier: processIdentifier)
                let state = surface.microphoneState(for: kind)
                if state != .unknown { return state }
            }
            return .unknown
        }.value
    }

    private func confirmMicrophoneState(
        _ desired: QMicrophoneState,
        in processIdentifiers: [pid_t]
    ) async -> QMeetingControlResult {
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(125))
            if await observedMicrophoneState(in: processIdentifiers) == desired {
                return .confirmed(desired)
            }
        }
        return .failed
    }

    private func focusCallSurface(
        application: NSRunningApplication,
        processIdentifiers: [pid_t]
    ) async -> Bool {
        let kind = detectionKind
        _ = await Task.detached(priority: .userInitiated) {
            processIdentifiers.contains { processIdentifier in
                QMeetingAccessibilitySurface.raiseMeetingWindow(
                    processIdentifier: processIdentifier,
                    kind: kind
                )
            }
        }.value
        application.activate(options: [.activateAllWindows])
        let acceptedProcessIdentifiers = Set(processIdentifiers + [application.processIdentifier])
        for _ in 0..<16 {
            if let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               acceptedProcessIdentifiers.contains(frontmost) {
                // NSWorkspace reports the app as frontmost before Teams' Edge
                // WebView has actually accepted keyboard focus. Sending the
                // shortcut in that gap silently loses it, which is why the old
                // implementation's delay was important.
                try? await Task.sleep(for: .milliseconds(provider == .teams ? 300 : 120))
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private static func microphoneState(from state: QState?) -> QMicrophoneState {
        switch state {
        case .muted: .muted
        case .meeting: .unmuted
        default: .unknown
        }
    }

    private func inspect() async -> QMeetingSession {
        let applications = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        guard !applications.isEmpty else {
            activeApplication = nil
            return QMeetingSession(
                provider: provider,
                state: .available,
                isAvailable: false,
                canControl: canControl
            )
        }

        let trusted = canControl
        let processIdentifiers = relatedProcessIdentifiers(for: applications)
        let kind = detectionKind
        let accessibilityMatch: (pid_t, QState)? = if trusted {
            await Task.detached(priority: .utility) {
                var candidate: (pid_t, QState)?
                for processIdentifier in processIdentifiers {
                    let surface = QMeetingAccessibilitySurface(processIdentifier: processIdentifier)
                    if let state = surface.meetingState(for: kind) {
                        candidate = (processIdentifier, state)
                        if state == .muted { break }
                    }
                }
                return candidate
            }.value
        } else {
            nil
        }
        let nativeWindows = provider == .teams
            ? QMeetingNativeWindows.snapshot(ownedBy: Set(processIdentifiers))
            : QMeetingNativeWindows.Snapshot()
        let hasOpaqueTeamsCall = provider == .teams &&
            (QMeetingSurfaceClassifier.hasTeamsMeetingWindow(windowTitles: nativeWindows.titles) ||
             QMeetingSurfaceClassifier.hasTeamsCompactCallWindow(windowLayers: nativeWindows.layers))
        let detectedState: QState? = if let accessibilityMatch {
            accessibilityMatch.1
        } else if hasOpaqueTeamsCall {
            lastSnapshot?.isActive == true ? lastSnapshot?.state : .meeting
        } else {
            nil
        }
        if detectedState == nil {
            lastRequestedMicrophoneState = nil
        } else if accessibilityMatch != nil {
            lastRequestedMicrophoneState = Self.microphoneState(from: detectedState)
        }
        activeApplication = accessibilityMatch.flatMap { best in
            applications.first { $0.processIdentifier == best.0 }
        } ?? applications.first
        let providerIsAvailable = provider == .googleMeet ? detectedState != nil : true
        return QMeetingSession(
            provider: provider,
            state: detectedState ?? .available,
            isAvailable: providerIsAvailable,
            canControl: canControl,
            context: [
                "appRunning": "true",
                "bundleIdentifier": activeApplication?.bundleIdentifier ?? "",
                "detection": accessibilityMatch == nil && hasOpaqueTeamsCall ? "native-window" : "accessibility"
            ]
        )
    }

    private func relatedProcessIdentifiers(for applications: [NSRunningApplication]) -> [pid_t] {
        guard provider == .teams else { return applications.map(\.processIdentifier) }
        // New Teams hosts the useful accessibility tree in Edge WebView helper
        // processes rather than exclusively in the MSTeams process.
        let related = NSWorkspace.shared.runningApplications.filter { application in
            guard let executablePath = application.executableURL?.path else { return false }
            return applicationPaths.contains { executablePath.hasPrefix($0 + "/") }
        }
        return Array(Set((applications + related).map(\.processIdentifier))).sorted()
    }

    private static func postKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}

private enum QMeetingNativeWindows {
    struct Snapshot {
        var titles: [String] = []
        var layers: [Int] = []
    }

    static func snapshot(ownedBy processIdentifiers: Set<pid_t>) -> Snapshot {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return Snapshot() }
        var result = Snapshot()
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                  processIdentifiers.contains(owner) else { continue }
            if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
                result.titles.append(title)
            }
            if let layer = window[kCGWindowLayer as String] as? Int {
                result.layers.append(layer)
            }
        }
        return result
    }
}

struct QMeetingAccessibilitySurface {
    private var buttonLabels: [String] = []
    private var windowTitles: [String] = []
    private var microphoneToggleStates: [QMicrophoneState] = []

    init(processIdentifier: pid_t) {
        let root = AXUIElementCreateApplication(processIdentifier)
        collect(root)
    }

    func meetingState(for kind: QMeetingSurfaceKind) -> QState? {
        QMeetingSurfaceClassifier.state(
            buttonLabels: buttonLabels,
            windowTitles: windowTitles,
            kind: kind
        )
    }

    func microphoneState(for kind: QMeetingSurfaceKind) -> QMicrophoneState {
        guard meetingState(for: kind) != nil else { return .unknown }
        return microphoneState()
    }

    func microphoneState() -> QMicrophoneState {
        if let knownToggleState = microphoneToggleStates.first(where: { $0 != .unknown }) {
            return knownToggleState
        }
        return QMeetingControlVocabulary.microphoneState(buttonLabels: buttonLabels)
    }

    static func pressMicrophoneButton(
        processIdentifier: pid_t,
        shouldMute: Bool,
        kind: QMeetingSurfaceKind? = nil
    ) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        let roots: [AXUIElement]
        if let kind,
           let windows = valueAttribute(kAXWindowsAttribute, from: application) as? [AXUIElement] {
            roots = windows.filter { window in
                QMeetingAccessibilitySurface(root: window).meetingState(for: kind) != nil
            }
            guard !roots.isEmpty else { return false }
        } else {
            roots = [application]
        }
        return roots.contains { root in
            pressMicrophoneButton(in: root, shouldMute: shouldMute)
        }
    }

    private static func pressMicrophoneButton(
        in root: AXUIElement,
        shouldMute: Bool
    ) -> Bool {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count, index < 5_000 {
            let (element, depth) = queue[index]
            index += 1
            let role = stringAttribute(kAXRoleAttribute, from: element)
            if role == kAXButtonRole as String || role == kAXCheckBoxRole as String {
                let label = [
                    stringAttribute(kAXTitleAttribute, from: element),
                    stringAttribute(kAXDescriptionAttribute, from: element),
                    stringAttribute(kAXHelpAttribute, from: element)
                ].compactMap { $0 }.joined(separator: " ")
                if role == kAXCheckBoxRole as String,
                   let isOn = booleanAttribute(kAXValueAttribute, from: element) {
                    let currentState = QMeetingControlVocabulary.microphoneToggleState(
                        label: label,
                        isOn: isOn
                    )
                    if currentState != .unknown {
                        let desired: QMicrophoneState = shouldMute ? .muted : .unmuted
                        guard currentState != desired else { return true }
                        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                    }
                }
                if QMeetingControlVocabulary.buttonPerformsDesiredAction(
                    label: label,
                    shouldMute: shouldMute
                ) {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                }
            }
            guard depth < 16,
                  let children = valueAttribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return false
    }

    static func raiseMeetingWindow(
        processIdentifier: pid_t,
        kind: QMeetingSurfaceKind
    ) -> Bool {
        let root = AXUIElementCreateApplication(processIdentifier)
        guard let windows = valueAttribute(kAXWindowsAttribute, from: root) as? [AXUIElement] else {
            return false
        }
        for window in windows {
            let surface = QMeetingAccessibilitySurface(root: window)
            guard surface.meetingState(for: kind) != nil else { continue }
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        }
        return false
    }

    private init(root: AXUIElement) {
        collect(root)
    }

    private mutating func collect(_ root: AXUIElement) {
        // Teams nests the meeting toolbar roughly ten levels below its Edge
        // WebView. The old depth-first limit stopped immediately above the
        // actual Mute and Leave buttons. Breadth-first traversal finds all
        // windows fairly and keeps a hard cap for pathological web pages.
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count, index < 5_000 {
            let (element, depth) = queue[index]
            index += 1

            let role = stringAttribute(kAXRoleAttribute, from: element)
            let strings = [
                stringAttribute(kAXTitleAttribute, from: element),
                stringAttribute(kAXDescriptionAttribute, from: element),
                stringAttribute(kAXHelpAttribute, from: element),
                stringAttribute(kAXValueAttribute, from: element)
            ].compactMap { $0 }.filter { !$0.isEmpty }
            if role == kAXWindowRole as String {
                windowTitles.append(contentsOf: strings)
            } else if role == kAXButtonRole as String || role == kAXCheckBoxRole as String {
                buttonLabels.append(contentsOf: strings)
                if role == kAXCheckBoxRole as String,
                   let isOn = Self.booleanAttribute(kAXValueAttribute, from: element) {
                    microphoneToggleStates.append(
                        QMeetingControlVocabulary.microphoneToggleState(
                            label: strings.joined(separator: " "),
                            isOn: isOn
                        )
                    )
                }
            }

            guard depth < 16,
                  let children = valueAttribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
                continue
            }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        valueAttribute(attribute, from: element) as? String
    }

    private static func valueAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func booleanAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        guard let value = valueAttribute(attribute, from: element) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "1", "true", "on": return true
            case "0", "false", "off": return false
            default: return nil
            }
        }
        return nil
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        Self.stringAttribute(attribute, from: element)
    }

    private func valueAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        Self.valueAttribute(attribute, from: element)
    }

}
