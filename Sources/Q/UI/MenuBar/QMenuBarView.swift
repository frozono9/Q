import QCore
import SwiftUI

struct QMenuBarView: View {
    @ObservedObject var model: QAppModel
    @State private var editingDuration = false
    @State private var showingSettings = false
    @State private var showingSetup = false
    @State private var deviceNameDraft = "Q"
    @AppStorage(QAppModel.setupCompletedKey) private var setupCompleted = false
    @ObservedObject private var device: VirtualQDevice
    private let onPopoverHoverChanged: (Bool) -> Void

    init(
        model: QAppModel,
        onPopoverHoverChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
        device = model.virtualDevice
        self.onPopoverHoverChanged = onPopoverHoverChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showingSetup {
                setupView
            } else if showingSettings {
                generalSettings
            } else {
                currentStatus
                modeContext
                if model.selectedMode == .availability || model.selectedMode == .custom {
                    stateSection
                }
            }
            Divider()
            footer
        }
        // The normal surface should hug its content. Settings needs an explicit
        // height because its ScrollView otherwise reports a tiny intrinsic size
        // during the first in-place transition.
        .frame(width: 320, height: (showingSettings || showingSetup) ? 500 : nil, alignment: .top)
        .onHover(perform: onPopoverHoverChanged)
        .onChange(of: model.selectedMode) { _, _ in editingDuration = false }
        .onAppear {
            deviceNameDraft = model.physicalDeviceName
            if !setupCompleted { showingSetup = true }
        }
        .onChange(of: model.physicalDeviceIdentifier) { _, _ in
            deviceNameDraft = model.physicalDeviceName
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            QBrandMark(size: 24, lineWidth: 2.7)

            if showingSettings || showingSetup {
                Text(showingSetup ? "Set up Q" : "Settings")
                    .font(.headline.weight(.semibold))
            } else {
                Menu {
                    ForEach(QMode.primaryModes) { mode in
                        Button {
                            model.selectMode(mode)
                        } label: {
                            Label(mode.name, systemImage: mode.systemImage)
                        }
                    }
                    if !model.customModes.isEmpty {
                        Divider()
                        Section("Custom modes") {
                            ForEach(model.customModes) { mode in
                                Button {
                                    model.selectCustomMode(mode.id)
                                } label: {
                                    Label(mode.name, systemImage: mode.systemImage)
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        model.openCustomModeEditor()
                    } label: {
                        Label("New Custom Mode…", systemImage: "plus")
                    }
                    Button {
                        model.importCustomMode()
                    } label: {
                        Label("Import Custom Mode…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Text(model.currentModeName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Change Q mode")
            }

            Spacer(minLength: 12)

            if showingSettings || showingSetup {
                connectionIndicator(
                    label: model.isPhysicalDeviceConnected ? model.physicalDeviceName : "No Q",
                    isActive: model.isPhysicalDeviceConnected
                )
            } else {
                connectionIndicators
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var connectionIndicators: some View {
        VStack(alignment: .trailing, spacing: 3) {
            connectionIndicator(
                label: model.isPhysicalDeviceConnected ? "\(model.physicalDeviceName) connected" : "No Q",
                isActive: model.isPhysicalDeviceConnected
            )

            if let integrationLabel = model.integrationConnectionLabel {
                connectionIndicator(
                    label: integrationLabel,
                    isActive: model.isIntegrationConnectionActive
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func connectionIndicator(label: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currentStatus: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    ForEach(Array(device.currentScene.leds.enumerated()), id: \.offset) { _, led in
                        LEDDot(state: led, size: 18)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Three Q lights showing \(device.currentScene.name)")
            }

            Button {
                device.sendButtonEvent(.singlePress)
            } label: {
                HStack(spacing: 10) {
                Image(systemName: "button.programmable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.currentButtonActionTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help("Same action as pressing the Q device")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var modeContext: some View {
        switch model.selectedMode {
        case .pomodoro:
            pomodoroContext

        case .aiAgents where model.agentSlots.count > 1:
            agentContext

        case .meetings:
            meetingContext

        case .custom:
            HStack {
                Text("\(model.activePreset.states.count) custom states")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit Mode") {
                    model.openCustomModeEditor(model.selectedCustomModeID)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

        default:
            EmptyView()
        }
    }

    private var meetingContext: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Control provider")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                meetingProviderPicker
            }

            Text(meetingProviderDetail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var pomodoroContext: some View {
        VStack(spacing: 12) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.pomodoroConfiguration.focusMinutes)m focus · \(model.pomodoroConfiguration.breakMinutes)m break")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.selectedStateID != "idle" {
                Button("Reset") {
                    if let idle = model.activePreset.states.first(where: { $0.id == "idle" }) {
                        model.apply(idle)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Stop the timer and return to its configured duration")
            }

            Button {
                editingDuration.toggle()
            } label: {
                Label(editingDuration ? "Close" : "Edit", systemImage: "timer")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, editingDuration ? 0 : 12)
        if editingDuration {
            PomodoroDurationEditor(
                focusMinutes: model.pomodoroConfiguration.focusMinutes,
                breakMinutes: model.pomodoroConfiguration.breakMinutes
            ) { focus, rest in
                model.setPomodoroFocusMinutes(focus)
                model.setPomodoroBreakMinutes(rest)
                editingDuration = false
            } onCancel: {
                editingDuration = false
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        }
    }

    private var agentContext: some View {
        VStack(spacing: 0) {
            ForEach(model.agentSlots) { slot in
                if slot.index > 0 {
                    Divider().padding(.leading, 24)
                }

                Button {
                    model.focusAgent(slot.session)
                } label: {
                    HStack(spacing: 9) {
                        LEDDot(state: slot.session.ledState, size: 10)
                        Text("\(slot.session.source) · \(slot.session.displayName)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(slot.session.state.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(model.selectedMode == .custom ? "Choose state" : "Set availability")

                LazyVGrid(columns: stateColumns, spacing: 4) {
                    ForEach(model.activePreset.states) { preset in
                        StateOption(
                            preset: preset,
                            isSelected: model.selectedStateID == preset.id
                        ) {
                            model.apply(preset)
                        }
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var statusTitle: String {
        if model.selectedMode == .pomodoro {
            return model.pomodoroTimeText
        }
        if model.selectedMode == .aiAgents, model.agentSlots.count > 1 {
            return "\(model.agentSlots.count) agents"
        }
        return model.currentStatePreset?.name ?? device.currentScene.name
    }

    private var statusDetail: String {
        switch model.selectedMode {
        case .aiAgents:
            if model.agentSlots.count > 1 {
                return "Press Q to open the agent that needs you most."
            }
            if let session = model.agentSlots.first?.session {
                return "\(session.source) · \(session.displayName)"
            }
            if model.isCodexIntegrationAvailable || model.isClaudeCodeConnected {
                return "Watching for agent activity"
            }
            return "Open Codex or connect Claude Code."
        case .meetings:
            if let provider = model.selectedMeetingProvider {
                if !model.isMeetingProviderAvailable(provider) {
                    return "Open \(provider.name) to use it."
                }
                if model.selectedStateID == "free" {
                    return "Watching \(provider.name)"
                }
            } else if !model.isAnyMeetingIntegrationAvailable {
                return "Open Discord, Zoom, Meet, or Teams."
            }
            if model.selectedStateID == "free" {
                return "Watching connected meeting apps"
            }
            return model.activeMeetingSession.map { "\($0.provider.name) call" }
                ?? "Allow Accessibility access to control meetings."
        case .pomodoro:
            switch model.selectedStateID {
            case "idle": return "Ready to focus"
            case "focus": return "Focus · time remaining"
            case "paused": return "Focus paused"
            case "break": return "Break · time remaining"
            default: return "Phase complete"
            }
        case .availability:
            return "Choose what Q signals to people around you."
        case .relaxing:
            return "A quiet, continuously shifting color gradient."
        case .custom:
            return "Your lights and button actions."
        default:
            return ""
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                if showingSetup {
                    showingSetup = false
                } else {
                    showingSettings.toggle()
                }
            } label: {
                Label(
                    (showingSettings || showingSetup) ? "Done" : "Settings",
                    systemImage: (showingSettings || showingSetup) ? "checkmark" : "gearshape"
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                model.quit()
            } label: {
                Image(systemName: "power")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .help("Quit Q")
        }
        .font(.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsSection(title: "Your Q", systemImage: "circle.hexagongrid.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.isPhysicalDeviceConnected ? "Connected" : "Not connected")
                                    .font(.callout.weight(.medium))
                                Text(model.isPhysicalDeviceConnected ? "Ready on this Mac" : "Connect Q over USB-C")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(model.isPhysicalDeviceConnected ? Color.green : Color.secondary)
                                .frame(width: 8, height: 8)
                        }

                        if model.isPhysicalDeviceConnected {
                            Divider()
                            HStack {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                TextField("Q", text: $deviceNameDraft)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 135)
                                    .onSubmit { model.setPhysicalDeviceName(deviceNameDraft) }
                                if deviceNameDraft != model.physicalDeviceName {
                                    Button("Save") { model.setPhysicalDeviceName(deviceNameDraft) }
                                        .buttonStyle(.link)
                                }
                            }

                            Divider()
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text("Brightness")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int((model.deviceBrightness * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: Binding(
                                        get: { model.deviceBrightness },
                                        set: { model.setDeviceBrightness($0) }
                                    ),
                                    in: 0.1...1,
                                    step: 0.05
                                )
                                .accessibilityLabel("Device brightness")
                            }
                        }

                        if model.isFirmwareUpdateAvailable || model.firmwareUpdateState != .idle {
                            firmwareUpdateCard
                        } else if model.isPhysicalDeviceConnected {
                            Divider()
                            deviceDetailRow("Firmware", value: model.firmwareStatusLabel)
                        }
                    }
                }

                settingsSection(title: "Connected apps", systemImage: "link") {
                    VStack(alignment: .leading, spacing: 9) {
                        integrationStatusRow(
                            name: "Codex",
                            status: model.isCodexIntegrationAvailable ? "Ready" : "Not detected",
                            available: model.isCodexIntegrationAvailable
                        )
                        HStack {
                            Circle()
                                .fill(model.isClaudeCodeConnected ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text("Claude Code").font(.caption)
                            Spacer()
                            Text(model.isClaudeCodeConnected ? "Connected" : (model.isClaudeCodeInstalled ? "Not connected" : "Not installed"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button(model.isClaudeCodeConnected ? "Disconnect" : (model.isClaudeCodeInstalled ? "Connect" : "Install…")) {
                                if model.isClaudeCodeConnected {
                                    model.disconnectClaudeCode()
                                } else if model.isClaudeCodeInstalled {
                                    model.connectClaudeCode()
                                } else {
                                    model.openClaudeCodeInstallGuide()
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption2)
                        }
                        if let error = model.claudeCodeConnectionError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        integrationStatusRow(
                            name: "Accessibility",
                            status: model.isAccessibilityAuthorized ? "Granted" : "Required",
                            available: model.isAccessibilityAuthorized
                        )
                        if !model.isAccessibilityAuthorized {
                            Button("Grant Accessibility…") {
                                model.requestAccessibilityAuthorization()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                        Divider()
                        HStack {
                            Text("Meeting control")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            meetingProviderPicker
                        }
                        meetingIntegrationRow(.discord)
                        meetingIntegrationRow(.zoom)
                        meetingIntegrationRow(.googleMeet)
                        meetingIntegrationRow(.teams)
                        Text("Auto follows the active call. Pin a provider only when you need to override it.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                settingsSection(title: "Custom modes", systemImage: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.customModes.isEmpty ? "Create your own mode" : "\(model.customModes.count) saved")
                                    .font(.callout.weight(.medium))
                                Text("Define lights, states, and button actions.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.customModes.isEmpty ? "Create…" : "Manage…") {
                                model.openCustomModeEditor(model.selectedCustomModeID)
                            }
                        }
                        Button("Import .qmode…") { model.importCustomMode() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }

                settingsSection(title: "Diagnostics", systemImage: "stethoscope") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(model.isRunningLightTest ? "Testing…" : "Test lights") {
                                model.runLightTest()
                            }
                            .disabled(!model.isPhysicalDeviceConnected || model.isRunningLightTest)

                            Button(model.isAwaitingButtonTest ? "Press Q now…" : "Test button") {
                                model.beginButtonTest()
                            }
                            .disabled(!model.isPhysicalDeviceConnected || model.isAwaitingButtonTest)
                        }
                        .buttonStyle(.bordered)

                        if let result = model.buttonTestResult {
                            Label(result, systemImage: result == "No press detected" ? "exclamationmark.circle" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(result == "No press detected" ? Color.secondary : Color.green)
                        } else if model.isAwaitingButtonTest {
                            Text("Press the physical Q button now.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Divider()
                        deviceDetailRow("Q app", value: model.appVersionLabel)
                        deviceDetailRow("Identifier", value: model.physicalDeviceIdentifier ?? "—")
                        deviceDetailRow("Firmware", value: model.physicalFirmwareVersion ?? "—")
                        deviceDetailRow(
                            "Port",
                            value: model.physicalPortPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—"
                        )
                        if !model.recentDiagnosticEvents.isEmpty {
                            Divider()
                            Text("Recent activity")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            ForEach(Array(model.recentDiagnosticEvents.prefix(4))) { event in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Image(systemName: diagnosticIcon(for: event.outcome))
                                        .font(.caption2)
                                        .foregroundStyle(event.outcome == .failed ? Color.red : Color.secondary)
                                        .frame(width: 12)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        if !event.detail.isEmpty {
                                            Text(event.detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                        Divider()
                        HStack {
                            Button("Setup check…") {
                                showingSettings = false
                                showingSetup = true
                            }
                            Button("Copy report") { model.copyDiagnosticReport() }
                                .help("Copies technical status only—never chat content")
                        }
                        .buttonStyle(.bordered)
                        Text("Reports contain technical status only, never chats or prompts.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
    }

    private func integrationStatusRow(name: String, status: String, available: Bool) -> some View {
        HStack {
            Circle()
                .fill(available ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(name)
                .font(.caption)
            Spacer()
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func diagnosticIcon(for outcome: QDiagnosticOutcome) -> String {
        switch outcome {
        case .information: "circle"
        case .confirmed: "checkmark.circle.fill"
        case .unconfirmed: "questionmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up Q")
                        .font(.title2.weight(.semibold))
                    Text("A quick hardware and integration check before you start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                setupRow(
                    title: "Physical Q",
                    detail: model.isPhysicalDeviceConnected ? "\(model.physicalDeviceName) connected" : "Connect it over USB-C",
                    ready: model.isPhysicalDeviceConnected
                )
                setupRow(
                    title: "Firmware",
                    detail: model.firmwareStatusLabel,
                    ready: model.isPhysicalDeviceConnected && !model.isFirmwareUpdateAvailable
                )
                if model.isFirmwareUpdateAvailable || model.firmwareUpdateState != .idle {
                    firmwareUpdateCard
                }
                setupRow(
                    title: "Accessibility",
                    detail: model.isAccessibilityAuthorized ? "Granted" : "Needed for Codex and meeting controls",
                    ready: model.isAccessibilityAuthorized
                )
                if !model.isAccessibilityAuthorized {
                    Button("Grant Accessibility…") { model.requestAccessibilityAuthorization() }
                        .buttonStyle(.bordered)
                }
                setupRow(
                    title: "Codex",
                    detail: model.isCodexIntegrationAvailable ? "Detected" : "Open Codex to connect it",
                    ready: model.isCodexIntegrationAvailable
                )
                setupRow(
                    title: "Claude Code",
                    detail: model.isClaudeCodeConnected
                        ? "Connected"
                        : (model.isClaudeCodeInstalled ? "Installed · connect Q hooks" : "Optional · not installed"),
                    ready: model.isClaudeCodeConnected,
                    optional: true
                )
                if model.isClaudeCodeInstalled, !model.isClaudeCodeConnected {
                    Button("Connect Claude Code") { model.connectClaudeCode() }
                        .buttonStyle(.bordered)
                }
                setupRow(
                    title: "Discord",
                    detail: model.isDiscordIntegrationAvailable ? "Detected" : "Optional · open Discord to test",
                    ready: model.isDiscordIntegrationAvailable,
                    optional: true
                )
                setupRow(
                    title: "Zoom",
                    detail: model.isZoomIntegrationAvailable ? "Detected" : "Optional · open Zoom to test",
                    ready: model.isZoomIntegrationAvailable,
                    optional: true
                )
                setupRow(
                    title: "Google Meet",
                    detail: model.isGoogleMeetIntegrationAvailable ? "Call detected" : "Optional · no Meet call detected",
                    ready: model.isGoogleMeetIntegrationAvailable,
                    optional: true
                )
                setupRow(
                    title: "Microsoft Teams",
                    detail: model.isTeamsIntegrationAvailable ? "Detected" : "Optional · open Teams to test",
                    ready: model.isTeamsIntegrationAvailable,
                    optional: true
                )

                HStack(spacing: 8) {
                    Button(model.isRunningLightTest ? "Testing…" : "Test lights") { model.runLightTest() }
                        .disabled(!model.isPhysicalDeviceConnected || model.isRunningLightTest)
                    Button(model.isAwaitingButtonTest ? "Press Q now…" : "Test button") { model.beginButtonTest() }
                        .disabled(!model.isPhysicalDeviceConnected || model.isAwaitingButtonTest)
                }
                .buttonStyle(.bordered)

                if let result = model.buttonTestResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }

                Button("Finish setup") {
                    setupCompleted = true
                    showingSetup = false
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)

                Text("Q never copies chat content into diagnostics. Microphone access belongs to Codex because Q only triggers Codex's own Dictate control.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    private func setupRow(title: String, detail: String, ready: Bool, optional: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ready ? "checkmark.circle.fill" : (optional ? "circle.dashed" : "exclamationmark.circle"))
                .foregroundStyle(ready ? Color.green : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var firmwareUpdateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Firmware").font(.callout.weight(.medium))
                    Text(firmwareUpdateMessage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.firmwareUpdateState.isRunning { ProgressView().controlSize(.small) }
            }
            if let progress = model.firmwareUpdateProgress,
               model.firmwareUpdateState.isRunning {
                ProgressView(value: progress)
            }
            if model.isFirmwareUpdateAvailable,
               !model.firmwareUpdateState.isRunning {
                Button("Update to \(QFirmwareUpdater.currentVersion)") { model.updateFirmware() }
                    .buttonStyle(.borderedProminent)
            }
            if case let .failed(message) = model.firmwareUpdateState {
                Text(message).font(.caption2).foregroundStyle(.red).textSelection(.enabled)
                Button("Retry") { model.updateFirmware() }.buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
    }

    private var firmwareUpdateMessage: String {
        switch model.firmwareUpdateState {
        case .idle: model.firmwareStatusLabel
        case .preparing: "Preparing Q…"
        case .flashing: "Installing safely. Keep Q connected."
        case .reconnecting: "Restarting and verifying Q…"
        case .succeeded: "Updated and verified · \(QFirmwareUpdater.currentVersion)"
        case .failed: "Update could not be completed. Q can be retried."
        }
    }

    private func deviceDetailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func meetingIntegrationRow(_ provider: QMeetingProvider) -> some View {
        let available = model.isMeetingProviderAvailable(provider)
        return HStack {
            Circle()
                .fill(available ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(provider.name).font(.caption)
            Spacer()
            Text(model.meetingProviderStatus(provider))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var meetingProviderPicker: some View {
        Picker("Control provider", selection: Binding(
            get: { model.meetingProviderSelection },
            set: { model.setMeetingProviderSelection($0) }
        )) {
            ForEach(QMeetingProviderSelection.allCases) { selection in
                Text(selection.name).tag(selection)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private var meetingProviderDetail: String {
        guard let provider = model.selectedMeetingProvider else {
            return "Auto follows whichever call is active."
        }
        return model.isMeetingProviderAvailable(provider)
            ? "Button actions are pinned to \(provider.name)."
            : "Open \(provider.name) to enable its button actions."
    }

    private var stateColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct LEDDot: View {
    let state: QLEDState
    var size: CGFloat = 16

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.82))
            .overlay {
                Circle()
                    .fill(Color(state.color))
                    .opacity(state.isEnabled ? state.brightness : 0)
            }
            .frame(width: size, height: size)
            .overlay {
                Circle().stroke(.black.opacity(0.16), lineWidth: 0.7)
            }
            .shadow(
                color: state.isEnabled ? Color(state.color).opacity(state.brightness * 0.58) : .clear,
                radius: size * 0.26
            )
            .animation(.easeOut(duration: 0.8), value: state.isEnabled)
            .animation(.linear(duration: 1), value: state.brightness)
    }
}

private struct StateOption: View {
    let preset: QStatePreset
    let isSelected: Bool
    let action: () -> Void

    private var representativeLED: QLEDState {
        preset.scene.leds.first(where: \.isEnabled) ?? .off
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(
                        representativeLED.isEnabled
                            ? Color(representativeLED.color)
                            : Color.white.opacity(0.78)
                    )
                    .frame(width: 9, height: 9)
                    .overlay {
                        Circle().stroke(.black.opacity(0.14), lineWidth: 0.5)
                    }

                Text(preset.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 31)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .background(
                isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set state to \(preset.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension QState {
    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .waitingForUser, .permissionRequired: "Needs you"
        case .done: "Done"
        case .error, .failed: "Error"
        default: "Active"
        }
    }
}


private struct PomodoroDurationEditor: View {
    @State private var focusText: String
    @State private var breakText: String
    @FocusState private var focusField: Bool
    let onSave: (Int, Int) -> Void
    let onCancel: () -> Void

    init(focusMinutes: Int, breakMinutes: Int,
         onSave: @escaping (Int, Int) -> Void, onCancel: @escaping () -> Void) {
        _focusText = State(initialValue: String(focusMinutes))
        _breakText = State(initialValue: String(breakMinutes))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var valid: Bool {
        guard let focus = Int(focusText), let rest = Int(breakText) else { return false }
        return (1...180).contains(focus) && (1...60).contains(rest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Focus")
                Spacer()
                TextField("Minutes", text: $focusText)
                    .focused($focusField)
                    .accessibilityLabel("Focus minutes")
                    .frame(width: 64)
                Text("min").foregroundStyle(.secondary)
            }
            HStack {
                Text("Break")
                Spacer()
                TextField("Minutes", text: $breakText)
                    .accessibilityLabel("Break minutes")
                    .frame(width: 64)
                Text("min").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes)m") { focusText = String(minutes) }
                        .buttonStyle(.bordered)
                        .help("Set focus to \(minutes) minutes")
                }
            }
            Text(valid
                 ? "Keeps time already spent in the current session."
                 : "Enter whole minutes: focus 1–180, break 1–60.")
                .font(.caption2)
                .foregroundStyle(valid ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Apply") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!valid)
            }
        }
        .font(.caption)
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .onSubmit { save() }
        .onAppear { focusField = true }
    }

    private func save() {
        guard valid, let focus = Int(focusText), let rest = Int(breakText) else { return }
        onSave(focus, rest)
    }
}
