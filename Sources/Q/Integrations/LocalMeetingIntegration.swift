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
            activeApplication.activate(options: [.activateAllWindows])
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

    func toggleMute() -> Bool {
        guard let activeApplication else {
            focus()
            return false
        }
        guard canControl else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }
        activeApplication.activate(options: [.activateAllWindows])
        // Teams' WebView does not expose its mute button or state through AX.
        // Keep our state in sync with the shortcut we are about to deliver;
        // the window-presence detector below will retain it while the call is active.
        if provider == .teams, var snapshot = lastSnapshot, snapshot.isActive {
            snapshot.state = snapshot.state == .muted ? .meeting : .muted
            snapshot.updatedAt = .now
            lastSnapshot = snapshot
        }
        let keyCode = muteKeyCode
        let flags = muteFlags
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                return
            }
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    /// Sets, rather than toggles, the microphone state. This is used for
    /// push-to-talk so a missed/repeated button event cannot invert the result.
    func setMuted(_ shouldMute: Bool) -> Bool {
        let applications = bundleIdentifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        guard let application = activeApplication ?? applications.first else {
            focus()
            return false
        }
        guard canControl else {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return false
        }

        activeApplication = application
        let processIdentifiers = relatedProcessIdentifiers(for: applications)
        let previousState = lastSnapshot?.state
        let shouldFallbackToggle = shouldMute
            ? previousState != .muted
            : previousState != .meeting

        if var snapshot = lastSnapshot {
            snapshot.state = shouldMute ? .muted : .meeting
            snapshot.updatedAt = .now
            lastSnapshot = snapshot
        }

        application.activate(options: [.activateAllWindows])
        let keyCode = muteKeyCode
        let flags = muteFlags
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            let pressed = await Task.detached(priority: .userInitiated) {
                for processIdentifier in processIdentifiers {
                    if QMeetingAccessibilitySurface.pressMicrophoneButton(
                        processIdentifier: processIdentifier,
                        shouldMute: shouldMute
                    ) {
                        return true
                    }
                }
                return false
            }.value
            guard !pressed, shouldFallbackToggle else { return }
            Self.postKeyboardShortcut(keyCode: keyCode, flags: flags)
        }
        return true
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
            ? QMeetingNativeWindows.snapshot(ownedBy: Set(applications.map(\.processIdentifier)))
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
        activeApplication = accessibilityMatch.flatMap { best in
            applications.first { $0.processIdentifier == best.0 }
        } ?? applications.first
        return QMeetingSession(
            provider: provider,
            state: detectedState ?? .available,
            isAvailable: true,
            canControl: canControl,
            context: [
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

    private static func postKeyboardShortcut(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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

private struct QMeetingAccessibilitySurface {
    private var buttonLabels: [String] = []
    private var windowTitles: [String] = []

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

    static func pressMicrophoneButton(processIdentifier: pid_t, shouldMute: Bool) -> Bool {
        let root = AXUIElementCreateApplication(processIdentifier)
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
                ].compactMap { $0 }.joined(separator: " ").lowercased()
                let isUnmute = label.contains("unmute") || label.contains("turn on microphone") ||
                    label.contains("activar microfono") || label.contains("reactivar audio")
                let isMute = !isUnmute && (label.contains("mute mic") ||
                    label.contains("mute microphone") || label.contains("turn off microphone") ||
                    label.contains("silenciar") || label.contains("desactivar microfono"))
                if (shouldMute && isMute) || (!shouldMute && isUnmute) {
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

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        Self.stringAttribute(attribute, from: element)
    }

    private func valueAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        Self.valueAttribute(attribute, from: element)
    }

}
