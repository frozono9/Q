import AppKit
import Combine
import OSLog
import QCore
import UniformTypeIdentifiers

@MainActor
final class QAppModel: ObservableObject {
    static let shared = QAppModel()

    let virtualDevice: VirtualQDevice

    @Published private(set) var selectedMode: QMode = .aiAgents
    @Published private(set) var selectedStateID = "idle"
    @Published private(set) var availabilityControlMode: QAvailabilityControlMode = .manual
    @Published private(set) var agentSessions: [QAgentSession] = []
    @Published private(set) var isCodexIntegrationAvailable = false
    @Published private(set) var isDiscordIntegrationAvailable = false
    @Published private(set) var isDiscordControlAuthorized = false
    @Published private(set) var pomodoroConfiguration: QPomodoroConfiguration
    @Published private(set) var pomodoroRemainingSeconds: Int
    @Published private(set) var gestureSettings: QGestureSettings
    @Published private(set) var customModes: [QCustomModeDefinition]
    @Published private(set) var selectedCustomModeID: UUID?

    private var selectedStateByMode: [QMode: String] = [
        .aiAgents: "idle",
        .availability: "available",
        .meetings: "free",
        .pomodoro: "idle"
    ]
    private var selectedCustomStateByMode: [UUID: UUID] = [:]
    private var pomodoroStateID = "idle"
    private var nextPomodoroPhaseID = "break"
    private var pomodoroPhaseTotalSeconds: Int
    private var pomodoroDeadline: Date?
    private var pomodoroTimerTask: Task<Void, Never>?
    private var virtualWindowController: VirtualQWindowController?
    private var customModeEditorController: QCustomModeEditorWindowController?
    private var buttonEventTask: Task<Void, Never>?
    private let codexIntegration = CodexLocalIntegration()
    private let discordIntegration = DiscordLocalIntegration()
    private let logger = Logger(subsystem: "app.q", category: "application")
    private static let gestureSettingsKey = "QGestureSettings"
    private static let customModesKey = "QCustomModes"

    init(
        virtualDevice: VirtualQDevice = VirtualQDevice(),
        pomodoroConfiguration: QPomodoroConfiguration = QPomodoroConfiguration()
    ) {
        self.virtualDevice = virtualDevice
        self.pomodoroConfiguration = pomodoroConfiguration
        let savedCustomModes = Self.loadCustomModes()
        gestureSettings = Self.loadGestureSettings()
        customModes = savedCustomModes
        selectedCustomModeID = savedCustomModes.first?.id
        pomodoroRemainingSeconds = pomodoroConfiguration.focusMinutes * 60
        pomodoroPhaseTotalSeconds = pomodoroConfiguration.focusMinutes * 60
    }

    func start() async {
        do {
            try await virtualDevice.connect()
            if let initialState = activePreset.defaultState {
                applyFactoryPreset(initialState)
            }
            startListeningForButtonEvents()
            startCodexIntegration()
            startDiscordIntegration()
            showVirtualQ()
        } catch {
            logger.error("Could not connect Virtual Q: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isVirtualQVisible: Bool {
        virtualWindowController?.isVisible == true
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
            if (selectedStateID == "meeting" || selectedStateID == "muted"),
               !isDiscordControlAuthorized {
                return "Enable Discord control"
            }
            switch selectedStateID {
            case "meeting": return "Mute Discord"
            case "muted": return "Unmute Discord"
            default: return "Open Discord"
            }
        case .pomodoro:
            switch pomodoroStateID {
            case "focus": return "Pause timer"
            case "paused": return "Resume timer"
            case "break": return "End break"
            case "finished": return "Start next phase"
            default: return "Start \(pomodoroConfiguration.focusMinutes)-minute timer"
            }
        case .builds: return "Open build"
        case .custom:
            guard let action = activeCustomState?.buttonMapping.singlePress else { return "Custom action" }
            return action.kind == .inheritGlobal ? gestureSettings.singlePress.name : action.kind.name
        }
    }

    var connectionLabel: String {
        switch selectedMode {
        case .aiAgents:
            return isCodexIntegrationAvailable ? "Codex live" : "Codex offline"
        case .meetings:
            return isDiscordIntegrationAvailable ? "Discord live" : "Discord offline"
        default:
            return virtualDevice.isConnected ? "Connected" : "Offline"
        }
    }

    var isConnectionActive: Bool {
        switch selectedMode {
        case .aiAgents: return isCodexIntegrationAvailable
        case .meetings: return isDiscordIntegrationAvailable
        default: return virtualDevice.isConnected
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
    }

    private func startCodexIntegration() {
        codexIntegration.start { [weak self] snapshot in
            guard let self else { return }
            isCodexIntegrationAvailable = snapshot.isAvailable
            updateAgentSessions(snapshot.sessions)
        }
    }

    private func startDiscordIntegration() {
        isDiscordControlAuthorized = discordIntegration.canControlDiscord
        discordIntegration.start { [weak self] snapshot in
            guard let self else { return }
            isDiscordIntegrationAvailable = snapshot.isDiscordRunning
            isDiscordControlAuthorized = discordIntegration.canControlDiscord
            updateMeetingState(snapshot.state)
        }
    }

    private func updateMeetingState(_ state: QState) {
        let id: String
        switch state {
        case .meeting: id = "meeting"
        case .muted: id = "muted"
        default: id = "free"
        }
        guard selectedStateByMode[.meetings] != id else { return }
        selectedStateByMode[.meetings] = id
        guard selectedMode == .meetings,
              let preset = QModeCatalog.meetings.states.first(where: { $0.id == id }) else { return }
        applyFactoryPreset(preset)
    }

    private func handleButtonEvent(_ event: QButtonEvent) {
        let trigger: QButtonTrigger = switch event {
        case .singlePress: .singlePress
        case .doublePress: .doublePress
        case .longPress: .longPress
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
        }
        performGestureAction(assignment, event: event)
        showGestureStatus()
    }

    func setGestureAction(_ action: QGestureAction, for event: QButtonEvent) {
        switch event {
        case .singlePress: gestureSettings.singlePress = action
        case .doublePress: gestureSettings.doublePress = action
        case .longPress: gestureSettings.longPress = action
        }
        if let data = try? JSONEncoder().encode(gestureSettings) {
            UserDefaults.standard.set(data, forKey: Self.gestureSettingsKey)
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
                }
                performCustomAction(state.buttonMapping.action(for: trigger))
                return
            }
            guard let activeState = currentStatePreset else { return }
            let trigger: QButtonTrigger = switch event {
            case .singlePress: .singlePress
            case .doublePress: .doublePress
            case .longPress: .longPress
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
        case .cycleScene:
            cyclePrimaryAvailabilityState()
        case .setState(let state):
            applyState(matching: state)
        case .toggleMeetingMute:
            let willMute = selectedStateID != "muted"
            if discordIntegration.toggleMute() {
                isDiscordControlAuthorized = true
                updateMeetingState(willMute ? .muted : .meeting)
            } else {
                isDiscordControlAuthorized = discordIntegration.canControlDiscord
            }
        case .focusMeetingApplication:
            discordIntegration.focusDiscord()
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

    func toggleVirtualQ() {
        if isVirtualQVisible {
            virtualWindowController?.hide()
        } else {
            showVirtualQ()
        }
        objectWillChange.send()
    }

    func showVirtualQ() {
        if virtualWindowController == nil {
            virtualWindowController = VirtualQWindowController(device: virtualDevice)
        }
        virtualWindowController?.show()
        objectWillChange.send()
    }

    func apply(_ scene: QScene) {
        Task {
            do {
                try await virtualDevice.apply(scene: scene)
            } catch {
                logger.error("Could not apply scene: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
