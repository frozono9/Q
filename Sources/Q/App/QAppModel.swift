import AppKit
import Combine
import OSLog
import QCore

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

    private var selectedStateByMode: [QMode: String] = [
        .aiAgents: "idle",
        .availability: "available",
        .meetings: "free",
        .pomodoro: "idle"
    ]
    private var pomodoroStateID = "idle"
    private var nextPomodoroPhaseID = "break"
    private var pomodoroDeadline: Date?
    private var pomodoroTimerTask: Task<Void, Never>?
    private var virtualWindowController: VirtualQWindowController?
    private var buttonEventTask: Task<Void, Never>?
    private let codexIntegration = CodexLocalIntegration()
    private let discordIntegration = DiscordLocalIntegration()
    private let logger = Logger(subsystem: "app.q", category: "application")

    init(
        virtualDevice: VirtualQDevice = VirtualQDevice(),
        pomodoroConfiguration: QPomodoroConfiguration = QPomodoroConfiguration()
    ) {
        self.virtualDevice = virtualDevice
        self.pomodoroConfiguration = pomodoroConfiguration
        pomodoroRemainingSeconds = pomodoroConfiguration.focusMinutes * 60
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
        QModeCatalog.preset(for: selectedMode)
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
            if let session = agentSlots.first?.session {
                return "Open \(session.displayName)"
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
        case .custom: return "Run custom action"
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
        guard QMode.primaryModes.contains(mode) else { return }
        selectedMode = mode
        let stateID = mode == .pomodoro
            ? pomodoroStateID
            : selectedStateByMode[mode] ?? QModeCatalog.preset(for: mode).defaultStateID
        guard let preset = QModeCatalog.preset(for: mode).states.first(where: { $0.id == stateID }) else {
            return
        }
        applyFactoryPreset(preset)
    }

    func apply(_ preset: QStatePreset) {
        guard !selectedMode.isExternallyManaged else { return }
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
        }
    }

    func setPomodoroBreakMinutes(_ minutes: Int) {
        pomodoroConfiguration.breakMinutes = min(max(minutes, 1), 60)
    }

    func updateAgentSessions(_ sessions: [QAgentSession]) {
        guard sessions != agentSessions else { return }
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
        guard let activeState = currentStatePreset else { return }

        let trigger: QButtonTrigger = switch event {
        case .singlePress: .singlePress
        case .doublePress: .doublePress
        case .longPress: .longPress
        }
        let mapping = activePreset.buttonMapping(for: activeState.state)
        performLocalAction(mapping.action(for: trigger))
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
        pomodoroRemainingSeconds = seconds
        pomodoroDeadline = Date.now.addingTimeInterval(TimeInterval(seconds))
        setPomodoroState(id)

        pomodoroTimerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let deadline = pomodoroDeadline {
                pomodoroRemainingSeconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                if pomodoroRemainingSeconds == 0 {
                    pomodoroTimerTask = nil
                    finishPomodoroPhase(next: id == "focus" ? "break" : "focus")
                    return
                }
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
