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
        VStack(alignment: .leading, spacing: 18) {
            header
            currentStatus
            modeSection
            stateSection
            footer
        }
        .padding(18)
        .frame(width: 312)
    }

    private var header: some View {
        HStack(spacing: 9) {
            QBrandMark(size: 22, lineWidth: 2.7)
            Text("Q")
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(device.isConnected ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(device.isConnected ? "Connected" : "Offline")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.primary.opacity(0.055), in: Capsule())
        }
    }

    private var currentStatus: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(Array(device.currentScene.leds.enumerated()), id: \.offset) { _, led in
                    LEDDot(state: led)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.currentScene.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(model.selectedMode.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current state: \(device.currentScene.name), mode: \(model.selectedMode.name)")
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MODE")

            Menu {
                ForEach(QMode.allCases) { mode in
                    Button {
                        model.selectMode(mode)
                    } label: {
                        Label(mode.name, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.selectedMode.systemImage)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(model.selectedMode.name)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.primary.opacity(0.07), lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("STATE")
                Spacer()
                if model.activePreset.supportsMultiSource {
                    Text("Multi-source ready")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            LazyVGrid(columns: stateColumns, spacing: 7) {
                ForEach(model.activePreset.states) { preset in
                    StateChip(
                        preset: preset,
                        isSelected: model.selectedStateID == preset.id
                    ) {
                        model.apply(preset)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 9) {
            Divider()

            HStack(spacing: 8) {
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
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help("Quit Q")
            }

            if let event = device.lastButtonEvent {
                HStack(spacing: 5) {
                    Image(systemName: "button.programmable")
                    Text(event.displayName)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
    }

    private var stateColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 7),
            GridItem(.flexible(), spacing: 7)
        ]
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }
}

private struct LEDDot: View {
    let state: QLEDState

    var body: some View {
        Circle()
            .fill(state.isEnabled ? Color(state.color) : Color.white.opacity(0.82))
            .frame(width: 16, height: 16)
            .overlay {
                Circle().stroke(.black.opacity(0.16), lineWidth: 0.7)
            }
            .shadow(
                color: state.isEnabled ? Color(state.color).opacity(state.brightness * 0.65) : .clear,
                radius: 5
            )
    }
}

private struct StateChip: View {
    let preset: QStatePreset
    let isSelected: Bool
    let action: () -> Void

    private var representativeLED: QLEDState {
        preset.scene.leds.first(where: \.isEnabled) ?? .off
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(
                        representativeLED.isEnabled
                            ? Color(representativeLED.color)
                            : Color.white.opacity(0.75)
                    )
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle().stroke(.black.opacity(0.14), lineWidth: 0.5)
                    }
                Text(preset.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.055),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set state to \(preset.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension QButtonEvent {
    var displayName: String {
        switch self {
        case .singlePress: "Single press"
        case .doublePress: "Double press"
        case .longPress: "Long press"
        }
    }
}
