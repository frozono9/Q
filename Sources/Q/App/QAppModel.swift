import AppKit
import ApplicationServices
import Combine
import OSLog
import QCore
import UniformTypeIdentifiers

@MainActor
final class QAppModel: ObservableObject {
    static let shared = QAppModel()

    let virtualDevice: VirtualQDevice
    let physicalDevice: SerialQDevice

    @Published private(set) var selectedMode: QMode = .aiAgents
    @Published private(set) var selectedStateID = "idle"
    @Published private(set) var availabilityControlMode: QAvailabilityControlMode = .manual
    @Published private(set) var agentSessions: [QAgentSession] = []
    @Published private(set) var isCodexIntegrationAvailable = false
    @Published private(set) var isDiscordIntegrationAvailable = false
    @Published private(set) var isDiscordControlAuthorized = false
    @Published private(set) var isZoomIntegrationAvailable = false
    @Published private(set) var isGoogleMeetIntegrationAvailable = false
    @Published private(set) var isTeamsIntegrationAvailable = false
    @Published private(set) var activeMeetingSession: QMeetingSession?
    @Published private(set) var meetingProviderSelection: QMeetingProviderSelection
    @Published private(set) var pomodoroConfiguration: QPomodoroConfiguration
    @Published private(set) var pomodoroRemainingSeconds: Int
    @Published private(set) var gestureSettings: QGestureSettings
    @Published private(set) var customModes: [QCustomModeDefinition]
    @Published private(set) var selectedCustomModeID: UUID?
    @Published private(set) var isPhysicalDeviceConnected = false
    @Published private(set) var physicalFirmwareVersion: String?
    @Published private(set) var physicalDeviceIdentifier: String?
    @Published private(set) var physicalDeviceName = "Q"
    @Published private(set) var physicalPortPath: String?
    @Published private(set) var deviceBrightness: Double
    @Published private(set) var isRunningLightTest = false
    @Published private(set) var isAwaitingButtonTest = false
    @Published private(set) var buttonTestResult: String?
    @Published private(set) var firmwareUpdateState: QFirmwareUpdateState = .idle
    @Published private(set) var firmwareUpdateProgress: Double?
    @Published private(set) var firmwareRecoveryPortPath: String?

    private var selectedStateByMode: [QMode: String] = [
        .aiAgents: "idle",
        .availability: "available",
        .meetings: "free",
        .pomodoro: "idle",
        .relaxing: "flow"
    ]
    private var selectedCustomStateByMode: [UUID: UUID] = [:]
    private var pomodoroStateID = "idle"
    private var nextPomodoroPhaseID = "break"
    private var pomodoroPhaseTotalSeconds: Int
    private var pomodoroDeadline: Date?
    private var pomodoroTimerTask: Task<Void, Never>?
    private var customModeEditorController: QCustomModeEditorWindowController?
    private var buttonEventTask: Task<Void, Never>?
    private var physicalButtonEventTask: Task<Void, Never>?
    private var physicalConnectionTask: Task<Void, Never>?
    private var lightTestTask: Task<Void, Never>?
    private var buttonTestTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []
    private var unscaledScene: QScene?
    private var meetingSessions: [QMeetingProvider: QMeetingSession] = [:]
    private var meetingPushToTalkProvider: QMeetingProvider?
    private var contextualHoldInProgress: QContextualHold?
    private let codexIntegration = CodexLocalIntegration()
    private let discordIntegration = DiscordLocalIntegration()
    private let zoomIntegration = LocalMeetingIntegration(
        provider: .zoom,
        bundleIdentifiers: ["us.zoom.xos"],
        applicationPaths: ["/Applications/zoom.us.app"],
        detectionKind: .zoom,
        muteKeyCode: 0,
        muteFlags: [.maskCommand, .maskShift]
    )
    private let teamsIntegration = LocalMeetingIntegration(
        provider: .teams,
        bundleIdentifiers: ["com.microsoft.teams2", "com.microsoft.teams"],
        applicationPaths: ["/Applications/Microsoft Teams.app"],
        detectionKind: .teams,
        muteKeyCode: 46,
        muteFlags: [.maskCommand, .maskShift]
    )
    private let googleMeetIntegration = LocalMeetingIntegration(
        provider: .googleMeet,
        bundleIdentifiers: [
            "com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac",
            "org.mozilla.firefox"
        ],
        applicationPaths: [
            "/Applications/Google Chrome.app", "/Applications/Safari.app",
            "/Applications/Microsoft Edge.app", "/Applications/Firefox.app"
        ],
        detectionKind: .googleMeet,
        muteKeyCode: 2,
        muteFlags: [.maskCommand]
    )
    private let firmwareUpdater = QFirmwareUpdater()
    private let logger = Logger(subsystem: "app.q", category: "application")
    private static let gestureSettingsKey = "QGestureSettings"
    private static let gestureSettingsVersionKey = "QGestureSettingsVersion"
    private static let customModesKey = "QCustomModes"
    private static let deviceBrightnessKey = "QDeviceBrightness"
    private static let deviceNamesKey = "QDeviceNames"
    private static let meetingProviderSelectionKey = "QMeetingProviderSelection"
    private static let presetReferenceBrightness = 0.85

    static let setupCompletedKey = "QSetupCompleted"

    init(
        virtualDevice: VirtualQDevice? = nil,
        physicalDevice: SerialQDevice? = nil,
        pomodoroConfiguration: QPomodoroConfiguration = QPomodoroConfiguration()
    ) {
        self.virtualDevice = virtualDevice ?? VirtualQDevice()
        self.physicalDevice = physicalDevice ?? SerialQDevice()
        self.pomodoroConfiguration = pomodoroConfiguration
        let savedCustomModes = Self.loadCustomModes()
        var savedGestureSettings = Self.loadGestureSettings()
        if UserDefaults.standard.integer(forKey: Self.gestureSettingsVersionKey) < 1 {
            savedGestureSettings.longPress = .contextual
            if let data = try? JSONEncoder().encode(savedGestureSettings) {
                UserDefaults.standard.set(data, forKey: Self.gestureSettingsKey)
            }
            UserDefaults.standard.set(1, forKey: Self.gestureSettingsVersionKey)
        }
        gestureSettings = savedGestureSettings
        customModes = savedCustomModes
        selectedCustomModeID = savedCustomModes.first?.id
        meetingProviderSelection = Self.loadMeetingProviderSelection()
        deviceBrightness = Self.loadDeviceBrightness()
        pomodoroRemainingSeconds = pomodoroConfiguration.focusMinutes * 60
        pomodoroPhaseTotalSeconds = pomodoroConfiguration.focusMinutes * 60

        self.physicalDevice.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                self?.isPhysicalDeviceConnected = connected
            }
            .store(in: &cancellables)
        self.physicalDevice.$firmwareVersion
            .sink { [weak self] in self?.physicalFirmwareVersion = $0 }
            .store(in: &cancellables)
        self.physicalDevice.$deviceIdentifier
            .sink { [weak self] identifier in
                self?.physicalDeviceIdentifier = identifier
                self?.physicalDeviceName = Self.loadDeviceName(for: identifier)
            }
            .store(in: &cancellables)
        self.physicalDevice.$portPath
            .sink { [weak self] in self?.physicalPortPath = $0 }
            .store(in: &cancellables)
    }

    func start() async {
        do {
            try await virtualDevice.connect()
            if let initialState = activePreset.defaultState {
                applyFactoryPreset(initialState)
            }
            startListeningForButtonEvents()
            startPhysicalDeviceConnection()
            startCodexIntegration()
            startMeetingIntegrations()
        } catch {
            logger.error("Could not connect Virtual Q: \(error.localizedDescription, privacy: .public)")
        }
    }

    var activePreset: QModePreset {
        if selectedMode == .custom, let customMode = activeCustomMode {
            return QModePreset(
                id: .custom,
                states: customMode.states.enumerated().map { index, state in
                    QStatePreset(
                        id: state.id.uuidString,
                        name: state.name,
                        state: .custom(state.id.uuidString),
                        scene: state.scene,
                        priority: index
                    )
                },
                defaultStateID: customMode.defaultStateID.uuidString,
                buttonMapping: QButtonMapping(),
                supportsMultiSource: false
            )
        }
        return QModeCatalog.preset(for: selectedMode)
    }

    var isAccessibilityAuthorized: Bool { AXIsProcessTrusted() }

    var isAnyMeetingIntegrationAvailable: Bool {
        isDiscordIntegrationAvailable || isZoomIntegrationAvailable ||
            isGoogleMeetIntegrationAvailable || isTeamsIntegrationAvailable
    }

    var isFirmwareUpdateAvailable: Bool {
        guard isPhysicalDeviceConnected else { return false }
        guard let physicalFirmwareVersion else { return true }
        return physicalFirmwareVersion.compare(
            QFirmwareUpdater.currentVersion,
            options: .numeric
        ) == .orderedAscending
    }

    var firmwareStatusLabel: String {
        guard isPhysicalDeviceConnected else { return "Connect Q to check" }
        guard let physicalFirmwareVersion else { return "Legacy firmware" }
        return isFirmwareUpdateAvailable
            ? "Update available · \(QFirmwareUpdater.currentVersion)"
            : "Up to date · \(physicalFirmwareVersion)"
    }

    var diagnosticReport: String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        Q Diagnostic Report
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        App: \(appVersion) (\(build))
        macOS: \(os)
        Q connected: \(isPhysicalDeviceConnected ? "yes" : "no")
        Device name: \(physicalDeviceName)
        Device identifier: \(physicalDeviceIdentifier ?? "unavailable")
        Firmware: \(physicalFirmwareVersion ?? "unavailable")
        Expected firmware: \(QFirmwareUpdater.currentVersion)
        Serial port: \(physicalPortPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unavailable")
        Accessibility: \(isAccessibilityAuthorized ? "granted" : "not granted")
        Codex detected: \(isCodexIntegrationAvailable ? "yes" : "no")
        Discord detected: \(isDiscordIntegrationAvailable ? "yes" : "no")
        Discord control: \(isDiscordControlAuthorized ? "available" : "not available")
        Zoom detected: \(isZoomIntegrationAvailable ? "yes" : "no")
        Google Meet detected: \(isGoogleMeetIntegrationAvailable ? "yes" : "no")
        Microsoft Teams detected: \(isTeamsIntegrationAvailable ? "yes" : "no")
        Meeting provider: \(meetingProviderSelection.name)
        Active meeting: \(activeMeetingSession?.provider.name ?? "none")
        Mode: \(currentModeName)
        State: \(selectedStateID)
        """
    }

    func requestAccessibilityAuthorization() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        objectWillChange.send()
    }

    func copyDiagnosticReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticReport, forType: .string)
    }

    func setPhysicalDeviceName(_ proposedName: String) {
        guard let identifier = physicalDeviceIdentifier else { return }
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((trimmed.isEmpty ? "Q" : trimmed).prefix(32))
        physicalDeviceName = name
        var names = Self.loadDeviceNames()
        names[identifier] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: Self.deviceNamesKey)
        }
    }

    func updateFirmware() {
        guard !firmwareUpdateState.isRunning,
              let portPath = physicalPortPath ?? firmwareRecoveryPortPath else { return }
        firmwareRecoveryPortPath = portPath
        firmwareUpdateState = .preparing
        firmwareUpdateProgress = nil
        Task { [weak self] in
            guard let self else { return }
            await physicalDevice.disconnect()
            try? await Task.sleep(for: .milliseconds(500))
            do {
                firmwareUpdateState = .flashing(progress: nil)
                try await firmwareUpdater.flash(portPath: portPath) { progress in
                    Task { @MainActor [weak self] in
                        self?.firmwareUpdateProgress = progress
                        self?.firmwareUpdateState = .flashing(progress: progress)
                    }
                }
                firmwareUpdateState = .reconnecting
                var verified = false
                for _ in 0..<12 {
                    try? await Task.sleep(for: .seconds(1))
                    do {
                        try await physicalDevice.connect()
                        verified = physicalDevice.firmwareVersion == QFirmwareUpdater.currentVersion
                        if verified { break }
                        await physicalDevice.disconnect()
                    } catch { }
                }
                guard verified else {
                    throw QFirmwareUpdater.UpdateError.processFailed(
                        "Q was flashed but did not reconnect with the expected version. Unplug it, reconnect it, and retry."
                    )
                }
                try? await physicalDevice.apply(scene: virtualDevice.currentScene)
                firmwareUpdateState = .succeeded
                firmwareRecoveryPortPath = nil
            } catch {
                firmwareUpdateState = .failed(error.localizedDescription)
            }
        }
    }

    var activeCustomMode: QCustomModeDefinition? {
        guard let selectedCustomModeID else { return nil }
        return customModes.first { $0.id == selectedCustomModeID }
    }

    var activeCustomState: QCustomStateDefinition? {
        guard let mode = activeCustomMode else { return nil }
        return mode.states.first { $0.id.uuidString == selectedStateID }
    }

    var currentModeName: String {
        selectedMode == .custom ? (activeCustomMode?.name ?? "Custom") : selectedMode.name
    }

    var currentStatePreset: QStatePreset? {
        activePreset.states.first { $0.id == selectedStateID }
    }

    var agentSlots: [QAgentSlot] {
        QAgentSlotResolver.resolve(agentSessions)
    }

    var currentButtonActionTitle: String {
        switch selectedMode {
        case .aiAgents:
            if !agentSlots.isEmpty {
                return "Open task in Codex"
            }
            switch selectedStateID {
            case "done": return "Open completed agent"
            case "error": return "Open failed agent"
            default: return "Focus agent UI"
            }
        case .availability:
            switch selectedStateID {
            case "available": return "Set Focus"
            case "focus": return "Set Busy / DND"
            case "busy": return "Set Available"
            case "away", "offline": return "Set Available"
            default: return "Change availability"
            }
        case .meetings:
            if let meeting = activeMeetingSession, !meeting.canControl {
                return "Enable meeting control"
            }
            switch selectedStateID {
            case "meeting": return "Mute \(activeMeetingSession?.provider.name ?? "meeting")"
            case "muted": return "Unmute \(activeMeetingSession?.provider.name ?? "meeting")"
            default:
                return selectedMeetingProvider.map { "Open \($0.name)" } ?? "Open meeting app"
            }
        case .pomodoro:
            switch pomodoroStateID {
            case "focus": return "Pause timer"
            case "paused": return "Resume timer"
            case "break": return "End break"
            case "finished": return "Start next phase"
            default: return "Start \(pomodoroConfiguration.focusMinutes)-minute timer"
            }
        case .relaxing: return "Restart gradient"
        case .builds: return "Open build"
        case .custom:
            guard let action = activeCustomState?.buttonMapping.singlePress else { return "Custom action" }
            return action.kind == .inheritGlobal ? gestureSettings.singlePress.name : action.kind.name
        }
    }

    var integrationConnectionLabel: String? {
        switch selectedMode {
        case .aiAgents:
            return isCodexIntegrationAvailable ? "Codex live" : "Codex offline"
        case .meetings:
            if let activeMeetingSession { return "\(activeMeetingSession.provider.name) live" }
            if let provider = selectedMeetingProvider {
                return isMeetingProviderAvailable(provider)
                    ? "\(provider.name) ready"
                    : "\(provider.name) closed"
            }
            return isAnyMeetingIntegrationAvailable ? "Meetings ready" : "No meeting apps"
        default:
            return nil
        }
    }

    var isIntegrationConnectionActive: Bool {
        switch selectedMode {
        case .aiAgents: return isCodexIntegrationAvailable
        case .meetings:
            if let provider = selectedMeetingProvider {
                return isMeetingProviderAvailable(provider)
            }
            return isAnyMeetingIntegrationAvailable
        default: return false
        }
    }

    var pomodoroTimeText: String {
        let minutes = pomodoroRemainingSeconds / 60
        let seconds = pomodoroRemainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func selectMode(_ mode: QMode) {
        if mode == .custom {
            guard let id = selectedCustomModeID ?? customModes.first?.id else { return }
            selectCustomMode(id)
            return
        }
        guard QMode.primaryModes.contains(mode) else { return }
        selectedMode = mode
        let stateID = mode == .pomodoro
            ? pomodoroStateID
            : selectedStateByMode[mode] ?? QModeCatalog.preset(for: mode).defaultStateID
        guard let preset = QModeCatalog.preset(for: mode).states.first(where: { $0.id == stateID }) else {
            return
        }
        applyFactoryPreset(preset)
        if mode == .aiAgents {
            updateAgentSessions(agentSessions, forceRefresh: true)
        }
        if mode == .pomodoro, stateID == "focus" || stateID == "break" {
            applyPomodoroProgress()
        }
    }

    func apply(_ preset: QStatePreset) {
        guard !selectedMode.isExternallyManaged else { return }
        if selectedMode == .custom,
           let stateID = UUID(uuidString: preset.id) {
            selectCustomState(stateID)
            return
        }
        if selectedMode == .pomodoro {
            selectPomodoroState(preset.id)
            return
        }
        if selectedMode == .availability {
            availabilityControlMode = .manual
        }
        applyFactoryPreset(preset)
    }

    func setAvailabilityControlMode(_ mode: QAvailabilityControlMode) {
        availabilityControlMode = mode
        if mode == .automatic {
            applyState(withID: "available")
        }
    }

    func setPomodoroFocusMinutes(_ minutes: Int) {
        pomodoroConfiguration.focusMinutes = min(max(minutes, 1), 180)
        if pomodoroStateID == "idle" {
            pomodoroRemainingSeconds = pomodoroConfiguration.focusMinutes * 60
            pomodoroPhaseTotalSeconds = pomodoroRemainingSeconds
        } else if pomodoroStateID == "focus" || pomodoroStateID == "paused" {
            resizePomodoroPhase(totalSeconds: pomodoroConfiguration.focusMinutes * 60)
        }
    }

    func setPomodoroBreakMinutes(_ minutes: Int) {
        pomodoroConfiguration.breakMinutes = min(max(minutes, 1), 60)
        if pomodoroStateID == "break" {
            resizePomodoroPhase(totalSeconds: pomodoroConfiguration.breakMinutes * 60)
        }
    }

    private func resizePomodoroPhase(totalSeconds: Int) {
        let now = Date.now
        let remaining = pomodoroDeadline.map { $0.timeIntervalSince(now) }
            ?? Double(pomodoroRemainingSeconds)
        let adjusted = QPomodoroProgress.adjustedRemaining(
            oldTotal: Double(pomodoroPhaseTotalSeconds),
            remaining: remaining,
            newTotal: Double(totalSeconds)
        )
        pomodoroPhaseTotalSeconds = totalSeconds
        pomodoroRemainingSeconds = Int(ceil(adjusted))
        guard adjusted > 0 else {
            finishPomodoroPhase(next: pomodoroStateID == "break" ? "focus" : "break")
            return
        }
        // Keep the existing task and pause state; only move its deadline.
        if pomodoroDeadline != nil {
            pomodoroDeadline = now.addingTimeInterval(adjusted)
        }
        applyPomodoroProgress()
    }

    func updateAgentSessions(_ sessions: [QAgentSession], forceRefresh: Bool = false) {
        guard forceRefresh || sessions != agentSessions else { return }
        agentSessions = sessions
        guard selectedMode == .aiAgents else { return }

        guard !sessions.isEmpty else {
            if let idle = activePreset.states.first(where: { $0.id == "idle" }) {
                applyFactoryPreset(idle)
            }
            return
        }

        let slots = agentSlots
        if slots.count > 1 {
            selectedStateID = "multiple-agents"
            selectedStateByMode[.aiAgents] = selectedStateID
            apply(QAgentSlotResolver.scene(for: slots))
        } else if let state = slots.first?.session.state,
                  let preset = activePreset.states.first(where: { $0.state == state }) {
            // A single agent uses the expressive full-device scene (for example,
            // the amber three-step chase). Per-agent LED slots begin at two agents.
            applyFactoryPreset(preset)
        }
    }

    private func applyFactoryPreset(_ preset: QStatePreset) {
        selectedStateID = preset.id
        selectedStateByMode[selectedMode] = preset.id
        apply(preset.scene)
    }

    private func startListeningForButtonEvents() {
        guard buttonEventTask == nil else { return }
        buttonEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in virtualDevice.buttonEvents {
                handleButtonEvent(event)
            }
        }
        physicalButtonEventTask = Task { [weak self] in
            guard let self else { return }
            for await event in physicalDevice.buttonEvents {
                if isAwaitingButtonTest {
                    if event == .longPressEnded { continue }
                    completeButtonTest(event)
                    continue
                }
                handleButtonEvent(event)
            }
        }
    }

    private func startPhysicalDeviceConnection() {
        guard physicalConnectionTask == nil else { return }
        physicalConnectionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !physicalDevice.isConnected && !firmwareUpdateState.isRunning {
                    do {
                        try await physicalDevice.connect()
                        try await physicalDevice.apply(scene: virtualDevice.currentScene)
                    } catch QDeviceError.noSerialDevice {
                        // Normal while Q is unplugged. Discovery retries quietly.
                    } catch {
                        logger.error(
                            "Physical Q connection failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func startCodexIntegration() {
        codexIntegration.start { [weak self] snapshot in
            guard let self else { return }
            isCodexIntegrationAvailable = snapshot.isAvailable
            updateAgentSessions(snapshot.sessions)
        }
    }

    private func startMeetingIntegrations() {
        isDiscordControlAuthorized = discordIntegration.canControlDiscord
        discordIntegration.start { [weak self] snapshot in
            guard let self else { return }
            isDiscordIntegrationAvailable = snapshot.isDiscordRunning
            isDiscordControlAuthorized = discordIntegration.canControlDiscord
            updateMeetingSession(
                QMeetingSession(
                    provider: .discord,
                    state: snapshot.state,
                    isAvailable: snapshot.isDiscordRunning,
                    canControl: discordIntegration.canControlDiscord
                )
            )
        }
        zoomIntegration.start { [weak self] in self?.updateMeetingSession($0) }
        teamsIntegration.start { [weak self] in self?.updateMeetingSession($0) }
        googleMeetIntegration.start { [weak self] in self?.updateMeetingSession($0) }
    }

    private func updateMeetingSession(_ incomingSession: QMeetingSession) {
        var session = incomingSession
        if meetingPushToTalkProvider == session.provider {
            session.state = .meeting
        }
        meetingSessions[session.provider] = session
        switch session.provider {
        case .discord:
            isDiscordIntegrationAvailable = session.isAvailable
            isDiscordControlAuthorized = session.canControl
        case .zoom:
            isZoomIntegrationAvailable = session.isAvailable
        case .googleMeet:
            isGoogleMeetIntegrationAvailable = session.isAvailable
        case .teams:
            isTeamsIntegrationAvailable = session.isAvailable
        }

        resolveMeetingSession()
    }

    private func resolveMeetingSession() {
        activeMeetingSession = QMeetingArbiter.resolve(
            Array(meetingSessions.values), selection: meetingProviderSelection
        )
        let state = activeMeetingSession?.state ?? .available
        let id: String
        switch state {
        case .meeting: id = "meeting"
        case .muted: id = "muted"
        default: id = "free"
        }
        selectedStateByMode[.meetings] = id
        if selectedMode == .meetings,
           let preset = QModeCatalog.meetings.states.first(where: { $0.id == id }) {
            applyFactoryPreset(preset)
        }
    }

    func setMeetingProviderSelection(_ selection: QMeetingProviderSelection) {
        meetingProviderSelection = selection
        UserDefaults.standard.set(selection.rawValue, forKey: Self.meetingProviderSelectionKey)
        resolveMeetingSession()
    }

    func isMeetingProviderAvailable(_ provider: QMeetingProvider) -> Bool {
        meetingSessions[provider]?.isAvailable == true
    }

    var selectedMeetingProvider: QMeetingProvider? {
        meetingProviderSelection.provider
    }

    private func handleButtonEvent(_ event: QButtonEvent) {
        logger.notice(
            "Button event=\(event.rawValue, privacy: .public) mode=\(self.selectedMode.rawValue, privacy: .public) meeting=\(self.activeMeetingSession?.provider.rawValue ?? "none", privacy: .public)"
        )
        if event == .longPressEnded {
            let hold = contextualHoldInProgress
            contextualHoldInProgress = nil
            if case .meeting = hold {
                endMeetingPushToTalk()
            } else if hold == .dictation {
                codexIntegration.endDictation()
            }
            return
        }
        if event == .longPress,
           gestureSettings.longPress == .contextual,
           selectedMode != .custom {
            guard contextualHoldInProgress == nil else { return }
            var hold = QContextualHold.resolve(mode: selectedMode, meeting: activeMeetingSession)
            if hold == .none, selectedMode == .meetings,
               let provider = preferredMeetingProviderForButton() {
                hold = .meeting(provider)
            }
            contextualHoldInProgress = hold
            switch hold {
            case .meeting(let provider): beginMeetingPushToTalk(provider: provider)
            case .dictation: codexIntegration.startDictation(in: agentSlots.first?.session)
            case .none: break
            }
            return
        }
        let trigger: QButtonTrigger = switch event {
        case .singlePress: .singlePress
        case .doublePress: .doublePress
        case .longPress: .longPress
        case .longPressEnded: .longPress
        }
        if selectedMode == .custom,
           let customAction = activeCustomState?.buttonMapping.action(for: trigger),
           customAction.kind != .inheritGlobal {
            performCustomAction(customAction)
            showGestureStatus()
            return
        }
        let assignment: QGestureAction = switch event {
        case .singlePress: gestureSettings.singlePress
        case .doublePress: gestureSettings.doublePress
        case .longPress: gestureSettings.longPress
        case .longPressEnded: gestureSettings.longPress
        }
        performGestureAction(assignment, event: event)
        let isCodexDictationHold = event == .longPress &&
            selectedMode == .aiAgents && assignment == .contextual
        if !isCodexDictationHold {
            showGestureStatus()
        }
    }

    func setGestureAction(_ action: QGestureAction, for event: QButtonEvent) {
        switch event {
        case .singlePress: gestureSettings.singlePress = action
        case .doublePress: gestureSettings.doublePress = action
        case .longPress: gestureSettings.longPress = action
        case .longPressEnded: gestureSettings.longPress = action
        }
        if let data = try? JSONEncoder().encode(gestureSettings) {
            UserDefaults.standard.set(data, forKey: Self.gestureSettingsKey)
        }
    }

    func setDeviceBrightness(_ brightness: Double) {
        deviceBrightness = min(max(brightness, 0.1), 1)
        UserDefaults.standard.set(deviceBrightness, forKey: Self.deviceBrightnessKey)
        if let unscaledScene {
            apply(unscaledScene)
        }
    }

    func runLightTest() {
        guard physicalDevice.isConnected else { return }
        lightTestTask?.cancel()
        let sceneToRestore = physicalDevice.currentScene
        isRunningLightTest = true
        lightTestTask = Task { [weak self] in
            guard let self else { return }
            let colors: [(String, QColor)] = [
                ("Red", .red), ("Green", .green), ("Blue", .blue), ("White", .white)
            ]
            for (name, color) in colors {
                guard !Task.isCancelled, physicalDevice.isConnected else { break }
                let scene = QScene(
                    name: "Test \(name)",
                    leds: Array(
                        repeating: QLEDState(color: color, brightness: 0.75),
                        count: QScene.ledCount
                    )
                )
                try? await physicalDevice.apply(scene: sceneWithDeviceBrightness(scene))
                try? await Task.sleep(for: .milliseconds(650))
            }
            if physicalDevice.isConnected {
                try? await physicalDevice.apply(scene: sceneToRestore)
            }
            isRunningLightTest = false
        }
    }

    func beginButtonTest() {
        guard physicalDevice.isConnected else { return }
        buttonTestTask?.cancel()
        buttonTestResult = nil
        isAwaitingButtonTest = true
        buttonTestTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
            guard let self, isAwaitingButtonTest else { return }
            isAwaitingButtonTest = false
            buttonTestResult = "No press detected"
        }
    }

    private func completeButtonTest(_ event: QButtonEvent) {
        buttonTestTask?.cancel()
        buttonTestTask = nil
        isAwaitingButtonTest = false
        buttonTestResult = switch event {
        case .singlePress: "Single press detected"
        case .doublePress: "Double press detected"
        case .longPress: "Long press detected"
        case .longPressEnded: "Long press released"
        }
    }

    private func performGestureAction(_ assignment: QGestureAction, event: QButtonEvent) {
        switch assignment {
        case .contextual:
            if selectedMode == .custom, let state = activeCustomState {
                let trigger: QButtonTrigger = switch event {
                case .singlePress: .singlePress
                case .doublePress: .doublePress
                case .longPress: .longPress
                case .longPressEnded: .longPress
                }
                performCustomAction(state.buttonMapping.action(for: trigger))
                return
            }
            guard let activeState = currentStatePreset else { return }
            let trigger: QButtonTrigger = switch event {
            case .singlePress: .singlePress
            case .doublePress: .doublePress
            case .longPress: .longPress
            case .longPressEnded: .longPress
            }
            performLocalAction(activePreset.buttonMapping(for: activeState.state).action(for: trigger))
        case .nextMode:
            cycleToNextMode()
        case .nextState:
            cycleEditableState()
        case .showStatus, .none:
            break
        }
    }

    private func cycleEditableState() {
        guard !selectedMode.isExternallyManaged else { return }
        if selectedMode == .custom {
            cycleCustomState(forward: true)
            return
        }
        guard selectedMode == .availability,
              let index = activePreset.states.firstIndex(where: { $0.id == selectedStateID }) else { return }
        apply(activePreset.states[(index + 1) % activePreset.states.count])
    }

    private func showGestureStatus() {
        NotificationCenter.default.post(
            name: .qShowGestureStatus,
            object: nil,
            userInfo: [
                "mode": currentModeName,
                "state": currentStatePreset?.name ?? virtualDevice.currentScene.name
            ]
        )
    }

    private static func loadGestureSettings() -> QGestureSettings {
        guard let data = UserDefaults.standard.data(forKey: gestureSettingsKey),
              let settings = try? JSONDecoder().decode(QGestureSettings.self, from: data) else {
            return QGestureSettings()
        }
        return settings
    }

    private static func loadDeviceBrightness() -> Double {
        guard UserDefaults.standard.object(forKey: deviceBrightnessKey) != nil else {
            return presetReferenceBrightness
        }
        return min(max(UserDefaults.standard.double(forKey: deviceBrightnessKey), 0.1), 1)
    }

    private static func loadMeetingProviderSelection() -> QMeetingProviderSelection {
        guard let rawValue = UserDefaults.standard.string(forKey: meetingProviderSelectionKey),
              let selection = QMeetingProviderSelection(rawValue: rawValue) else {
            return .automatic
        }
        return selection
    }

    private static func loadDeviceNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: deviceNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    private static func loadDeviceName(for identifier: String?) -> String {
        guard let identifier else { return "Q" }
        return loadDeviceNames()[identifier] ?? "Q"
    }

    private static func loadCustomModes() -> [QCustomModeDefinition] {
        guard let data = UserDefaults.standard.data(forKey: customModesKey),
              let modes = try? JSONDecoder().decode([QCustomModeDefinition].self, from: data) else {
            return []
        }
        return modes
    }

    private func performLocalAction(_ action: QButtonAction) {
        switch action {
        case .focusSource, .focusHighestPrioritySource, .openResult, .focusFailedSource:
            codexIntegration.focus(agentSlots.first?.session)
        case .focusMostRecentCodexChat:
            codexIntegration.focusMostRecentChat()
        case .startCodexDictation:
            codexIntegration.startDictation(in: agentSlots.first?.session)
        case .cycleScene:
            cyclePrimaryAvailabilityState()
        case .setState(let state):
            applyState(matching: state)
        case .toggleMeetingMute:
            toggleActiveMeetingMute()
        case .focusMeetingApplication:
            focusActiveMeetingApplication()
        case .startPomodoro:
            startNextPomodoroPhase()
        case .togglePomodoro:
            pomodoroStateID == "paused" ? resumePomodoro() : pausePomodoro()
        case .skipPomodoro:
            finishPomodoroPhase(next: "focus")
        case .turnOff:
            apply(.idle)
        case .none:
            break
        default:
            logger.debug("Button action awaits its integration target")
        }
    }

    private func toggleActiveMeetingMute() {
        guard let meeting = activeMeetingSession else {
            focusActiveMeetingApplication()
            return
        }
        let delivered: Bool = switch meeting.provider {
        case .discord: discordIntegration.toggleMute()
        case .zoom: zoomIntegration.toggleMute()
        case .googleMeet: googleMeetIntegration.toggleMute()
        case .teams: teamsIntegration.toggleMute()
        }
        guard delivered else { return }
        var optimistic = meeting
        optimistic.state = meeting.state == .muted ? .meeting : .muted
        optimistic.updatedAt = .now
        updateMeetingSession(optimistic)
    }

    private func beginMeetingPushToTalk(provider: QMeetingProvider) {
        guard meetingPushToTalkProvider == nil else { return }
        guard setMeetingMuted(false, provider: provider) else {
            logger.error("Push to talk could not unmute \(provider.rawValue, privacy: .public)")
            return
        }
        logger.notice("Push to talk began provider=\(provider.rawValue, privacy: .public)")
        meetingPushToTalkProvider = provider
        updateMeetingState(.meeting, provider: provider)
        NotificationCenter.default.post(
            name: .qShowGestureStatus,
            object: nil,
            userInfo: ["mode": provider.name, "state": "Push to talk"]
        )
    }

    private func endMeetingPushToTalk() {
        guard let provider = meetingPushToTalkProvider else { return }
        meetingPushToTalkProvider = nil
        guard setMeetingMuted(true, provider: provider) else {
            logger.error("Push to talk could not mute \(provider.rawValue, privacy: .public)")
            return
        }
        logger.notice("Push to talk ended provider=\(provider.rawValue, privacy: .public)")
        updateMeetingState(.muted, provider: provider)
    }

    private func setMeetingMuted(_ muted: Bool, provider: QMeetingProvider) -> Bool {
        switch provider {
        case .discord: discordIntegration.setMuted(muted)
        case .zoom: zoomIntegration.setMuted(muted)
        case .googleMeet: googleMeetIntegration.setMuted(muted)
        case .teams: teamsIntegration.setMuted(muted)
        }
    }

    private func updateMeetingState(_ state: QState, provider: QMeetingProvider) {
        let canControl = switch provider {
        case .discord: discordIntegration.canControlDiscord
        case .zoom: zoomIntegration.canControl
        case .googleMeet: googleMeetIntegration.canControl
        case .teams: teamsIntegration.canControl
        }
        var session = meetingSessions[provider] ?? QMeetingSession(
            provider: provider,
            state: state,
            isAvailable: true,
            canControl: canControl
        )
        session.state = state
        session.updatedAt = .now
        updateMeetingSession(session)
    }

    private func preferredMeetingProviderForButton() -> QMeetingProvider? {
        if let selectedMeetingProvider { return selectedMeetingProvider }
        if let activeMeetingSession { return activeMeetingSession.provider }

        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case "us.zoom.xos": return .zoom
        case "com.microsoft.teams2", "com.microsoft.teams": return .teams
        case "com.hnc.Discord": return .discord
        case "com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "org.mozilla.firefox":
            return .googleMeet
        default: break
        }

        let runningProviders = meetingSessions.values
            .filter(\.isAvailable)
            .map(\.provider)
        return runningProviders.count == 1 ? runningProviders[0] : nil
    }

    private func focusActiveMeetingApplication() {
        switch activeMeetingSession?.provider ?? selectedMeetingProvider {
        case .discord: discordIntegration.focusDiscord()
        case .zoom: zoomIntegration.focus()
        case .googleMeet: googleMeetIntegration.focus()
        case .teams: teamsIntegration.focus()
        case nil:
            if isZoomIntegrationAvailable { zoomIntegration.focus() }
            else if isTeamsIntegrationAvailable { teamsIntegration.focus() }
            else if isGoogleMeetIntegrationAvailable { googleMeetIntegration.focus() }
            else { discordIntegration.focusDiscord() }
        }
    }

    func selectCustomMode(_ id: UUID) {
        guard let mode = customModes.first(where: { $0.id == id }) else { return }
        selectedMode = .custom
        selectedCustomModeID = id
        let stateID = selectedCustomStateByMode[id].flatMap { candidate in
            mode.states.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? mode.defaultStateID
        selectCustomState(stateID)
    }

    func selectCustomState(_ id: UUID) {
        guard let mode = activeCustomMode,
              let state = mode.states.first(where: { $0.id == id }) else { return }
        selectedStateID = state.id.uuidString
        selectedStateByMode[.custom] = selectedStateID
        selectedCustomStateByMode[mode.id] = state.id
        apply(state.scene)
    }

    func saveCustomMode(_ definition: QCustomModeDefinition) {
        if let index = customModes.firstIndex(where: { $0.id == definition.id }) {
            customModes[index] = definition
        } else {
            customModes.append(definition)
        }
        persistCustomModes()
        selectCustomMode(definition.id)
    }

    func deleteCustomMode(_ id: UUID) {
        customModes.removeAll { $0.id == id }
        selectedCustomStateByMode[id] = nil
        persistCustomModes()
        if selectedMode == .custom, selectedCustomModeID == id {
            selectedCustomModeID = customModes.first?.id
            if let replacement = selectedCustomModeID {
                selectCustomMode(replacement)
            } else {
                selectMode(.aiAgents)
            }
        } else if selectedCustomModeID == id {
            selectedCustomModeID = customModes.first?.id
        }
    }

    func openCustomModeEditor(_ id: UUID? = nil) {
        let definition = id.flatMap { candidate in
            customModes.first { $0.id == candidate }
        } ?? QCustomModeDefinition.draft()
        customModeEditorController = QCustomModeEditorWindowController(
            definition: definition,
            isNew: id == nil,
            onSave: { [weak self] mode in
                self?.saveCustomMode(mode)
                self?.customModeEditorController = nil
            },
            onDelete: { [weak self] modeID in
                self?.deleteCustomMode(modeID)
                self?.customModeEditorController = nil
            },
            onClose: { [weak self] in
                self?.customModeEditorController = nil
            }
        )
        customModeEditorController?.show()
    }

    func importCustomMode() {
        let panel = NSOpenPanel()
        panel.title = "Import Custom Mode"
        panel.prompt = "Import"
        panel.allowedContentTypes = [UTType(filenameExtension: "qmode") ?? .data, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(QCustomModeDefinition.self, from: data)
            let states = decoded.states.map { state in
                QCustomStateDefinition(
                    id: state.id,
                    name: state.name,
                    scene: QScene(name: state.scene.name, leds: state.scene.leds),
                    buttonMapping: state.buttonMapping
                )
            }
            let imported = QCustomModeDefinition(
                id: customModes.contains(where: { $0.id == decoded.id }) ? UUID() : decoded.id,
                name: decoded.name,
                systemImage: decoded.systemImage,
                isIncludedInCycle: decoded.isIncludedInCycle,
                states: states,
                defaultStateID: decoded.defaultStateID
            )
            saveCustomMode(imported)
        } catch {
            logger.error("Could not import custom mode: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func persistCustomModes() {
        guard let data = try? JSONEncoder().encode(customModes) else { return }
        UserDefaults.standard.set(data, forKey: Self.customModesKey)
    }

    private enum ModeDestination: Equatable {
        case builtIn(QMode)
        case custom(UUID)
    }

    private func cycleToNextMode() {
        let destinations = QMode.primaryModes.map(ModeDestination.builtIn)
            + customModes.filter(\.isIncludedInCycle).map { ModeDestination.custom($0.id) }
        guard !destinations.isEmpty else { return }
        let current: ModeDestination
        if selectedMode == .custom, let selectedCustomModeID {
            current = .custom(selectedCustomModeID)
        } else {
            current = .builtIn(selectedMode)
        }
        let nextIndex = destinations.firstIndex(of: current).map { ($0 + 1) % destinations.count } ?? 0
        switch destinations[nextIndex] {
        case .builtIn(let mode): selectMode(mode)
        case .custom(let id): selectCustomMode(id)
        }
    }

    private func cycleCustomState(forward: Bool) {
        guard let mode = activeCustomMode,
              let index = mode.states.firstIndex(where: { $0.id.uuidString == selectedStateID }) else { return }
        let offset = forward ? 1 : mode.states.count - 1
        selectCustomState(mode.states[(index + offset) % mode.states.count].id)
    }

    private func performCustomAction(_ action: QCustomAction) {
        switch action.kind {
        case .inheritGlobal:
            break
        case .none:
            break
        case .nextState:
            cycleCustomState(forward: true)
        case .previousState:
            cycleCustomState(forward: false)
        case .turnOff:
            apply(.idle)
        case .openURL:
            guard let url = URL(string: action.value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            NSWorkspace.shared.open(url)
        case .openApplication:
            openApplication(named: action.value)
        case .runShortcut:
            let name = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name]
            do {
                try process.run()
            } catch {
                logger.error("Could not run Shortcut: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func openApplication(named value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(":") else { return }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        let candidates = ["/Applications/\(trimmed).app", "/System/Applications/\(trimmed).app"]
        guard let url = candidates.map(URL.init(fileURLWithPath:)).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func focusAgent(_ session: QAgentSession) {
        codexIntegration.focus(session)
    }

    private func cyclePrimaryAvailabilityState() {
        let cycle = ["available", "focus", "busy"]
        guard selectedMode == .availability,
              let currentIndex = cycle.firstIndex(of: selectedStateID) else { return }
        availabilityControlMode = .manual
        applyState(withID: cycle[(currentIndex + 1) % cycle.count])
    }

    private func applyState(matching state: QState) {
        guard let preset = activePreset.states.first(where: { $0.state == state }) else { return }
        applyFactoryPreset(preset)
    }

    private func applyState(withID id: String) {
        guard let preset = activePreset.states.first(where: { $0.id == id }) else { return }
        applyFactoryPreset(preset)
    }

    private func selectPomodoroState(_ id: String) {
        switch id {
        case "focus": startPomodoroPhase("focus", seconds: pomodoroConfiguration.focusMinutes * 60)
        case "break": startPomodoroPhase("break", seconds: pomodoroConfiguration.breakMinutes * 60)
        case "paused": pausePomodoro()
        case "finished": finishPomodoroPhase(next: nextPomodoroPhaseID)
        default: resetPomodoro()
        }
    }

    private func startNextPomodoroPhase() {
        if pomodoroStateID == "finished", nextPomodoroPhaseID == "break" {
            startPomodoroPhase("break", seconds: pomodoroConfiguration.breakMinutes * 60)
        } else {
            startPomodoroPhase("focus", seconds: pomodoroConfiguration.focusMinutes * 60)
        }
    }

    private func startPomodoroPhase(_ id: String, seconds: Int) {
        pomodoroTimerTask?.cancel()
        if !(id == "focus" && pomodoroStateID == "paused") {
            pomodoroPhaseTotalSeconds = seconds
        }
        pomodoroRemainingSeconds = seconds
        pomodoroDeadline = Date.now.addingTimeInterval(TimeInterval(seconds))
        setPomodoroState(id)
        applyPomodoroProgress()

        pomodoroTimerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let deadline = pomodoroDeadline {
                pomodoroRemainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if pomodoroRemainingSeconds == 0 {
                    pomodoroTimerTask = nil
                    finishPomodoroPhase(next: id == "focus" ? "break" : "focus")
                    return
                }
                applyPomodoroProgress()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func pausePomodoro() {
        guard pomodoroStateID == "focus" else { return }
        if let deadline = pomodoroDeadline {
            pomodoroRemainingSeconds = max(1, Int(ceil(deadline.timeIntervalSinceNow)))
        }
        pomodoroTimerTask?.cancel()
        pomodoroTimerTask = nil
        pomodoroDeadline = nil
        setPomodoroState("paused")
    }

    private func resumePomodoro() {
        guard pomodoroStateID == "paused" else { return }
        startPomodoroPhase("focus", seconds: max(1, pomodoroRemainingSeconds))
    }

    private func finishPomodoroPhase(next: String) {
        pomodoroTimerTask?.cancel()
        pomodoroTimerTask = nil
        pomodoroDeadline = nil
        pomodoroRemainingSeconds = 0
        nextPomodoroPhaseID = next
        setPomodoroState("finished")
    }

    private func resetPomodoro() {
        pomodoroTimerTask?.cancel()
        pomodoroTimerTask = nil
        pomodoroDeadline = nil
        nextPomodoroPhaseID = "break"
        pomodoroRemainingSeconds = pomodoroConfiguration.focusMinutes * 60
        pomodoroPhaseTotalSeconds = pomodoroRemainingSeconds
        setPomodoroState("idle")
    }

    private func setPomodoroState(_ id: String) {
        pomodoroStateID = id
        selectedStateByMode[.pomodoro] = id
        guard selectedMode == .pomodoro,
              let preset = QModeCatalog.pomodoro.states.first(where: { $0.id == id }) else { return }
        selectedStateID = id
        apply(preset.scene)
    }

    private func applyPomodoroProgress() {
        guard selectedMode == .pomodoro,
              pomodoroStateID == "focus" || pomodoroStateID == "break" else { return }
        apply(
            QPomodoroProgress.scene(
                remainingSeconds: pomodoroRemainingSeconds,
                totalSeconds: pomodoroPhaseTotalSeconds,
                isBreak: pomodoroStateID == "break"
            )
        )
    }

    func apply(_ scene: QScene) {
        unscaledScene = scene
        renderResolvedScene()
    }

    private func renderResolvedScene() {
        guard let baseScene = unscaledScene else { return }
        let renderedScene = sceneWithDeviceBrightness(baseScene)
        Task {
            do {
                try await virtualDevice.apply(scene: renderedScene)
            } catch {
                logger.error("Could not apply scene: \(error.localizedDescription, privacy: .public)")
            }
            guard physicalDevice.isConnected else { return }
            do {
                try await physicalDevice.apply(scene: renderedScene)
            } catch {
                logger.error("Could not update physical Q: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sceneWithDeviceBrightness(_ scene: QScene) -> QScene {
        let gain = deviceBrightness / Self.presetReferenceBrightness
        var adjusted = scene
        adjusted.leds = scene.leds.map { led in
            var adjustedLED = led
            adjustedLED.brightness = min(led.brightness * gain, 1)
            return adjustedLED
        }
        return adjusted
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
