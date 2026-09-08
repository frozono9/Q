import AppKit
import SwiftUI

struct QApp: App {
    @NSApplicationDelegateAdaptor(QAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class QAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()

        Task {
            await QAppModel.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.title = "Q"
        button.font = roundedMenuBarFont
        button.toolTip = "Q — ambient status"
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("Q")
        button.setAccessibilityHelp("Open Q controls")
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 312, height: 470)
        popover.contentViewController = NSHostingController(
            rootView: QMenuBarView(model: QAppModel.shared)
        )
    }

    private var roundedMenuBarFont: NSFont {
        let base = NSFont.systemFont(ofSize: 14, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return NSFont(descriptor: descriptor, size: 14) ?? base
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

QApp.main()
