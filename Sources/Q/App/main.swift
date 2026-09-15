import AppKit
import Combine
import OSLog
import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let qShowGestureStatus = Notification.Name("QShowGestureStatus")
}

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
    private static let statusItemAutosaveName = "QStatusItem"
    private static let deviceWatcherPlistName = "app.q.device-watcher.plist"
    private static let statusItemPositionKey =
        "NSStatusItem Preferred Position \(statusItemAutosaveName)"

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let gesturePopover = NSPopover()
    private var gestureStatusObserver: NSObjectProtocol?
    private var gestureDismissTask: Task<Void, Never>?
    private var deviceConnectionCancellable: AnyCancellable?
    private let logger = Logger(subsystem: "app.q", category: "status-item")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = QBrandAssets.appIcon
        configureStatusItem()
        configurePopover()
        configureGesturePopover()
        configureDeviceConnectionPresentation()
        registerLaunchAtLoginIfInstalled()
        registerDeviceWatcherIfInstalled()

        Task {
            await QAppModel.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let gestureStatusObserver {
            NotificationCenter.default.removeObserver(gestureStatusObserver)
        }
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        logger.notice("Reopening Q from its app icon")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.showPopover()
        }
        return true
    }

    private func configureStatusItem() {
        if UserDefaults.standard.object(forKey: Self.statusItemPositionKey) == nil {
            // New status items are otherwise placed at the far-left edge and can
            // land underneath a MacBook notch when the menu bar is crowded.
            UserDefaults.standard.set(280, forKey: Self.statusItemPositionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.statusItemAutosaveName
        guard let button = item.button else {
            logger.fault("AppKit did not create a status-item button")
            return
        }

        if let image = QBrandAssets.menuBarImage {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else {
            button.image = nil
            button.title = "Q"
            button.font = roundedMenuBarFont
        }
        button.toolTip = "Q — ambient status"
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("Q")
        button.setAccessibilityHelp("Open Q controls")
        item.isVisible = true
        statusItem = item
        logger.notice("Installed visible Q status item")

        Task { @MainActor in
            item.isVisible = true
            button.needsDisplay = true
            try? await Task.sleep(for: .milliseconds(250))
            let frame = button.window?.frame ?? .zero
            logger.notice(
                "Q status attached=\(button.window != nil) visible=\(item.isVisible) frame=\(NSStringFromRect(frame), privacy: .public)"
            )
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 470)
        popover.contentViewController = NSHostingController(
            rootView: QMenuBarView(model: QAppModel.shared)
        )
    }

    private func configureGesturePopover() {
        gesturePopover.behavior = .applicationDefined
        gesturePopover.animates = true
        gestureStatusObserver = NotificationCenter.default.addObserver(
            forName: .qShowGestureStatus,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let mode = notification.userInfo?["mode"] as? String ?? "Q"
            let state = notification.userInfo?["state"] as? String ?? ""
            Task { @MainActor [weak self] in
                self?.showGesturePopover(mode: mode, state: state)
            }
        }
    }

    private func configureDeviceConnectionPresentation() {
        deviceConnectionCancellable = QAppModel.shared.$isPhysicalDeviceConnected
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                logger.notice("Physical Q connected; revealing controls")
                showPopover()
            }
    }

    private func showGesturePopover(mode: String, state: String) {
        guard let button = statusItem?.button else { return }
        gestureDismissTask?.cancel()
        gesturePopover.contentSize = NSSize(width: 210, height: 68)
        gesturePopover.contentViewController = NSHostingController(
            rootView: QGestureStatusView(mode: mode, state: state)
        )
        if gesturePopover.isShown {
            gesturePopover.performClose(nil)
        }
        gesturePopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        gestureDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.gesturePopover.performClose(nil)
        }
    }

    private func registerLaunchAtLoginIfInstalled() {
        let installedBundle = URL(fileURLWithPath: "/Applications/Q.app").standardizedFileURL
        guard Bundle.main.bundleURL.standardizedFileURL == installedBundle else {
            logger.debug("Skipping launch-at-login registration for development build")
            return
        }

        let service = SMAppService.mainApp
        switch service.status {
        case .notRegistered, .notFound:
            register(service, name: "Q launch at login")
        case .enabled:
            logger.debug("Q is enabled at login")
        case .requiresApproval:
            logger.notice("Q launch at login is awaiting approval in System Settings")
        @unknown default:
            logger.error("Unknown launch-at-login registration state")
        }
    }

    private func registerDeviceWatcherIfInstalled() {
        let installedBundle = URL(fileURLWithPath: "/Applications/Q.app").standardizedFileURL
        guard Bundle.main.bundleURL.standardizedFileURL == installedBundle else {
            logger.debug("Skipping device watcher registration for development build")
            return
        }

        let service = SMAppService.agent(plistName: Self.deviceWatcherPlistName)
        switch service.status {
        case .notRegistered, .notFound:
            register(service, name: "Q device watcher")
        case .enabled:
            logger.debug("Q device watcher is enabled")
        case .requiresApproval:
            logger.notice("Q device watcher is awaiting approval in System Settings")
        @unknown default:
            logger.error("Unknown Q device watcher status")
        }
    }

    private func register(_ service: SMAppService, name: String) {
        do {
            try service.register()
            logger.notice("Registered \(name, privacy: .public); status=\(service.status.rawValue)")
        } catch {
            logger.error("Could not register \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private var roundedMenuBarFont: NSFont {
        let base = NSFont.systemFont(ofSize: 14, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
            return base
        }
        return NSFont(descriptor: descriptor, size: 14) ?? base
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        if gesturePopover.isShown {
            gesturePopover.performClose(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

}

private struct QGestureStatusView: View {
    let mode: String
    let state: String

    var body: some View {
        HStack(spacing: 11) {
            QBrandMark(size: 25, lineWidth: 2.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode).font(.headline)
                Text(state).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 210, height: 68)
    }
}

QApp.main()
