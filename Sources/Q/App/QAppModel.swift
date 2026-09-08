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

    private var virtualWindowController: VirtualQWindowController?
    private let logger = Logger(subsystem: "app.q", category: "application")

    init(virtualDevice: VirtualQDevice = VirtualQDevice()) {
        self.virtualDevice = virtualDevice
    }

    func start() async {
        do {
            try await virtualDevice.connect()
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

    func selectMode(_ mode: QMode) {
        selectedMode = mode
        let preset = QModeCatalog.preset(for: mode)
        guard let defaultState = preset.defaultState else { return }
        apply(defaultState)
    }

    func apply(_ preset: QStatePreset) {
        selectedStateID = preset.id
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
