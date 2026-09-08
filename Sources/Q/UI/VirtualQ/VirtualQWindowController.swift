import AppKit
import QCore
import SwiftUI

@MainActor
final class VirtualQWindowController {
    private let panel: NSPanel

    var isVisible: Bool { panel.isVisible }

    init(device: VirtualQDevice) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: VirtualQView(device: device))
        panel.setFrameAutosaveName("VirtualQPanel")
        panel.center()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
