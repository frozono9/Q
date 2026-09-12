import QCore
import SwiftUI

struct QMenuBarView: View {
    @ObservedObject var model: QAppModel
    @State private var editingDuration = false
    @State private var showingSettings = false
    @ObservedObject private var device: VirtualQDevice

    init(model: QAppModel) {
        self.model = model
        device = model.virtualDevice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showingSettings {
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
        .frame(width: 320)
        .onChange(of: model.selectedMode) { _, _ in editingDuration = false }
    }

    private var header: some View {
        HStack(spacing: 10) {
            QBrandMark(size: 24, lineWidth: 2.7)

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

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.isConnectionActive ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(model.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                        Text(slot.session.displayName)
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
                return "Codex · \(session.displayName)"
            }
            return model.isCodexIntegrationAvailable
                ? "Watching for agent activity"
                : "Start a local Codex task to connect."
        case .meetings:
            if !model.isDiscordIntegrationAvailable {
                return "Open Discord to connect."
            }
            if model.selectedStateID == "free" {
                return "No active Discord call"
            }
            return model.isDiscordControlAuthorized
                ? "Discord voice call"
                : "Allow Accessibility access to control Discord."
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
        case .custom:
            return "Your lights and button actions."
        default:
            return ""
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                showingSettings.toggle()
            } label: {
                Label(showingSettings ? "Done" : "Settings", systemImage: showingSettings ? "checkmark" : "gearshape")
            }
            .buttonStyle(.plain)

            if !showingSettings {
            Button {
                model.toggleVirtualQ()
            } label: {
                Label(
                    model.isVirtualQVisible ? "Hide preview" : "Show preview",
                    systemImage: model.isVirtualQVisible ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command, .shift])
            }

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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Button presses")
                    .font(.title3.weight(.semibold))
                Text("Choose what the physical Q button does for each gesture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            gestureSetting("Single press", event: .singlePress, selection: model.gestureSettings.singlePress)
            gestureSetting("Double press", event: .doublePress, selection: model.gestureSettings.doublePress)
            gestureSetting("Long press", event: .longPress, selection: model.gestureSettings.longPress)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom modes").font(.callout.weight(.medium))
                    Text(model.customModes.isEmpty ? "Create your own Q behavior." : "\(model.customModes.count) saved")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.customModes.isEmpty ? "Create…" : "Manage…") {
                    model.openCustomModeEditor(model.selectedCustomModeID)
                }
            }

            Button("Import .qmode…") {
                model.importCustomMode()
            }
            .buttonStyle(.link)

            Text("Every button press shows the resulting mode and state for five seconds.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func gestureSetting(
        _ title: String,
        event: QButtonEvent,
        selection: QGestureAction
    ) -> some View {
        HStack {
            Text(title).font(.callout.weight(.medium))
            Spacer()
            Picker(title, selection: Binding(
                get: { selection },
                set: { model.setGestureAction($0, for: event) }
            )) {
                ForEach(QGestureAction.allCases) { action in
                    Text(action.name).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 145)
        }
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
