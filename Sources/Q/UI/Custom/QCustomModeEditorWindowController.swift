import AppKit
import QCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class QCustomModeEditorWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(
        definition: QCustomModeDefinition,
        isNew: Bool,
        onSave: @escaping (QCustomModeDefinition) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = isNew ? "New Custom Mode" : "Edit Custom Mode"
        window.minSize = NSSize(width: 680, height: 540)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: QCustomModeEditorView(
                definition: definition,
                isNew: isNew,
                onSave: { value in
                    onSave(value)
                    window.close()
                },
                onDelete: { id in
                    onDelete(id)
                    window.close()
                },
                onCancel: { window.close() }
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct QCustomModeEditorView: View {
    @State private var draft: QCustomModeDefinition
    @State private var selectedStateID: UUID
    let isNew: Bool
    let onSave: (QCustomModeDefinition) -> Void
    let onDelete: (UUID) -> Void
    let onCancel: () -> Void

    init(
        definition: QCustomModeDefinition,
        isNew: Bool,
        onSave: @escaping (QCustomModeDefinition) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: definition)
        _selectedStateID = State(initialValue: definition.defaultStateID)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                stateSidebar
                    .frame(minWidth: 180, idealWidth: 195, maxWidth: 220)
                ScrollView {
                    if let index = selectedStateIndex {
                        stateEditor(state: bindingForState(at: index))
                            .padding(22)
                    }
                }
                .frame(minWidth: 440)
            }
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 540)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: draft.systemImage)
                    .font(.title2)
                    .frame(width: 30)
                TextField("Mode name", text: $draft.name)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
            }
            HStack {
                Picker("Icon", selection: $draft.systemImage) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Label(iconName(icon), systemImage: icon).tag(icon)
                    }
                }
                .frame(width: 190)
                Toggle("Include in double-press cycle", isOn: $draft.isIncludedInCycle)
                Spacer()
            }
            .font(.callout)
        }
        .padding(22)
    }

    private var stateSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedStateID) {
                ForEach(draft.states) { state in
                    HStack(spacing: 8) {
                        QEditorLEDStrip(scene: state.scene, size: 7)
                        Text(state.name).lineLimit(1)
                        if state.id == draft.defaultStateID {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(state.id)
                }
            }
            HStack {
                Button { addState() } label: { Image(systemName: "plus") }
                    .help("Add state")
                Button { removeSelectedState() } label: { Image(systemName: "minus") }
                    .disabled(draft.states.count == 1)
                    .help("Remove selected state")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .background(Color.primary.opacity(0.025))
    }

    private func stateEditor(state: Binding<QCustomStateDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                TextField("State name", text: state.name)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                Toggle("Default", isOn: Binding(
                    get: { draft.defaultStateID == state.wrappedValue.id },
                    set: { if $0 { draft.defaultStateID = state.wrappedValue.id } }
                ))
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 12) {
                editorLabel("LIGHTS")
                HStack {
                    QEditorLEDStrip(scene: state.wrappedValue.scene, size: 24)
                    Spacer()
                    Text("Live preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(0..<QScene.ledCount, id: \.self) { ledIndex in
                    ledEditor(led: bindingForLED(ledIndex, in: state), number: ledIndex + 1)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                editorLabel("BUTTON ACTIONS")
                CustomActionEditor(title: "Single press", action: state.buttonMapping.singlePress)
                CustomActionEditor(title: "Double press", action: state.buttonMapping.doublePress)
                CustomActionEditor(title: "Long press", action: state.buttonMapping.longPress)
                Text("Use general setting inherits the global gesture. Any other choice overrides it in this state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ledEditor(led: Binding<QLEDState>, number: Int) -> some View {
        HStack(spacing: 12) {
            Toggle("LED \(number)", isOn: led.isEnabled)
                .toggleStyle(.checkbox)
                .frame(width: 72, alignment: .leading)
            ColorPicker("", selection: Binding(
                get: { Color(led.wrappedValue.color) },
                set: { led.wrappedValue.color = QColor(nsColor: NSColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
            .disabled(!led.wrappedValue.isEnabled)
            Slider(value: led.brightness, in: 0...1)
                .frame(minWidth: 90)
                .disabled(!led.wrappedValue.isEnabled)
            Text("\(Int((led.wrappedValue.brightness * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Picker("Animation", selection: Binding(
                get: { led.wrappedValue.animation },
                set: { led.wrappedValue.animation = $0 }
            )) {
                ForEach(QAnimation.editorCases) { animation in
                    Text(animation.displayName).tag(animation)
                }
            }
            .labelsHidden()
            .frame(width: 125)
            .disabled(!led.wrappedValue.isEnabled)
        }
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Button("Delete Mode", role: .destructive) { onDelete(draft.id) }
            }
            Button("Export .qmode…") { exportDraft() }
            Spacer()
            Button("Cancel", action: onCancel)
            Button(isNew ? "Create Mode" : "Save Changes") {
                normalizeAndSave()
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private var selectedStateIndex: Int? {
        draft.states.firstIndex { $0.id == selectedStateID }
    }

    private func bindingForState(at index: Int) -> Binding<QCustomStateDefinition> {
        Binding(get: { draft.states[index] }, set: { draft.states[index] = $0 })
    }

    private func bindingForLED(_ index: Int, in state: Binding<QCustomStateDefinition>) -> Binding<QLEDState> {
        Binding(
            get: { state.wrappedValue.scene.leds[index] },
            set: { value in state.wrappedValue.scene.leds[index] = value }
        )
    }

    private func addState() {
        let state = QCustomStateDefinition(
            name: "State \(draft.states.count + 1)",
            scene: QScene(name: "State \(draft.states.count + 1)", leds: [.off, .off, .off])
        )
        draft.states.append(state)
        selectedStateID = state.id
    }

    private func removeSelectedState() {
        guard draft.states.count > 1,
              let index = selectedStateIndex else { return }
        let removed = draft.states.remove(at: index)
        if draft.defaultStateID == removed.id {
            draft.defaultStateID = draft.states[0].id
        }
        selectedStateID = draft.states[min(index, draft.states.count - 1)].id
    }

    private func normalizeAndSave() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in draft.states.indices {
            let fallback = "State \(index + 1)"
            let name = draft.states[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.states[index].name = name.isEmpty ? fallback : name
            draft.states[index].scene.name = draft.states[index].name
        }
        onSave(draft)
    }

    private func exportDraft() {
        let panel = NSSavePanel()
        panel.title = "Export Custom Mode"
        panel.nameFieldStringValue = "\(draft.name.replacingOccurrences(of: " ", with: "-")).qmode"
        panel.allowedContentTypes = [UTType(filenameExtension: "qmode") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(draft).write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    private func editorLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
    }

    private static let icons = [
        "slider.horizontal.3", "lightbulb", "bolt", "heart", "house", "moon.stars", "music.note", "gamecontroller"
    ]

    private func iconName(_ icon: String) -> String {
        switch icon {
        case "slider.horizontal.3": "Controls"
        case "lightbulb": "Light"
        case "bolt": "Energy"
        case "heart": "Heart"
        case "house": "Home"
        case "moon.stars": "Night"
        case "music.note": "Music"
        default: "Game"
        }
    }
}

private struct CustomActionEditor: View {
    let title: String
    @Binding var action: QCustomAction

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .frame(width: 88, alignment: .leading)
            Picker(title, selection: $action.kind) {
                ForEach(QCustomActionKind.allCases) { kind in
                    Text(kind.name).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 155)
            if action.kind.requiresValue {
                TextField(action.kind.valuePlaceholder, text: $action.value)
                    .textFieldStyle(.roundedBorder)
            } else {
                Spacer()
            }
        }
    }
}

private struct QEditorLEDStrip: View {
    let scene: QScene
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(Array(scene.leds.enumerated()), id: \.offset) { _, led in
                Circle()
                    .fill(led.isEnabled ? Color(led.color).opacity(led.brightness) : Color.secondary.opacity(0.18))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.black.opacity(0.16), lineWidth: 0.5))
            }
        }
    }
}

private extension QColor {
    init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.deviceRGB) ?? .white
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}

private extension QAnimation {
    static let editorCases: [QAnimation] = [.solid, .blink, .pulse, .flash, .fadeInOut, .chaseUp, .chaseDown]

    var displayName: String {
        switch self {
        case .solid: "Solid"
        case .blink: "Blink"
        case .pulse: "Pulse"
        case .flash: "Flash"
        case .flashThenSolid: "Flash, then solid"
        case .fadeInOut: "Fade in/out"
        case .chaseUp: "Chase forward"
        case .chaseDown: "Chase backward"
        case .bounce: "Bounce"
        case .progress: "Progress"
        case .alternating: "Alternating"
        case .gradientShift: "Gradient shift"
        case .rainbow: "Rainbow"
        }
    }
}
