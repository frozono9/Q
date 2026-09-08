import QCore
import SwiftUI

struct QMenuBarView: View {
    @ObservedObject var model: QAppModel
    @ObservedObject private var device: VirtualQDevice

    init(model: QAppModel) {
        self.model = model
        device = model.virtualDevice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            currentStatus
            Divider()
            modeSection
            modeContext
            Divider()
            stateSection
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            QBrandMark(size: 24, lineWidth: 2.7)

            Text(model.selectedMode.name)
                .font(.headline.weight(.semibold))
                .lineLimit(1)

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
                    Text("NOW SHOWING")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.65)
                        .foregroundStyle(.tertiary)
                    Text(device.currentScene.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
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

            HStack(spacing: 10) {
                Image(systemName: "button.programmable")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("PRESS Q")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    Text(model.currentButtonActionTitle)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Press Q to \(model.currentButtonActionTitle)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("Mode")

            Menu {
                ForEach(QMode.primaryModes) { mode in
                    Button {
                        model.selectMode(mode)
                    } label: {
                        Label(mode.name, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.selectedMode.systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(model.selectedMode.name)
                        .font(.body.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .frame(height: 30)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var modeContext: some View {
        switch model.selectedMode {
        case .availability:
            Picker(
                "Availability control",
                selection: Binding(
                    get: { model.availabilityControlMode },
                    set: { model.setAvailabilityControlMode($0) }
                )
            ) {
                ForEach(QAvailabilityControlMode.allCases, id: \.self) { controlMode in
                    Text(controlMode.name).tag(controlMode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

        case .pomodoro:
            pomodoroContext

        case .aiAgents where !model.agentSlots.isEmpty:
            agentContext

        default:
            EmptyView()
        }
    }

    private var pomodoroContext: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.pomodoroTimeText)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                Text(model.selectedStateID == "idle" ? "Focus duration" : "Remaining")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                Section("Focus") {
                    ForEach(QPomodoroConfiguration.commonFocusDurations, id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            model.setPomodoroFocusMinutes(minutes)
                        }
                    }
                    Stepper(
                        "Custom: \(model.pomodoroConfiguration.focusMinutes) min",
                        value: Binding(
                            get: { model.pomodoroConfiguration.focusMinutes },
                            set: { model.setPomodoroFocusMinutes($0) }
                        ),
                        in: 1...180
                    )
                }

                Section("Break") {
                    Stepper(
                        "\(model.pomodoroConfiguration.breakMinutes) minutes",
                        value: Binding(
                            get: { model.pomodoroConfiguration.breakMinutes },
                            set: { model.setPomodoroBreakMinutes($0) }
                        ),
                        in: 1...60
                    )
                }
            } label: {
                Label("Duration", systemImage: "timer")
                    .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
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
            sectionLabel("State")

            if model.selectedMode.isExternallyManaged {
                externallyManagedState
            } else {
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var externallyManagedState: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                LEDDot(
                    state: device.currentScene.leds.first(where: \.isEnabled) ?? .off,
                    size: 10
                )

                Text(model.currentStatePreset?.name ?? device.currentScene.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Label("Automatic", systemImage: "wave.3.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(externalStateSourceDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }

    private var externalStateSourceDescription: String {
        switch model.selectedMode {
        case .aiAgents:
            return model.agentSessions.isEmpty
                ? "Watching Codex / ChatGPT"
                : "Driven by live agent activity"
        case .meetings:
            return model.isDiscordIntegrationAvailable
                ? "Driven by Discord voice activity"
                : "Open Discord to connect"
        default:
            return "Managed by its connected source"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                model.toggleVirtualQ()
            } label: {
                Label(
                    model.isVirtualQVisible ? "Hide device" : "Show device",
                    systemImage: model.isVirtualQVisible ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q", modifiers: [.command, .shift])

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
            .fill(state.isEnabled ? Color(state.color) : Color.white.opacity(0.82))
            .frame(width: size, height: size)
            .overlay {
                Circle().stroke(.black.opacity(0.16), lineWidth: 0.7)
            }
            .shadow(
                color: state.isEnabled ? Color(state.color).opacity(state.brightness * 0.58) : .clear,
                radius: size * 0.26
            )
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
