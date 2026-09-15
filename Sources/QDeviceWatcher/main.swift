import AppKit
import Darwin
import Foundation
import IOKit
import OSLog

private final class QDeviceWatcher {
    private static let qBundleIdentifier = "app.q"
    private static let espressifVendorID = 0x303A
    private static let usbSerialJTAGProductID = 0x1001

    private let logger = Logger(subsystem: "app.q", category: "device-watcher")
    private let qApplicationURL: URL
    private var wasConnected = false

    init() {
        let executableURL = Self.absoluteExecutableURL()
        qApplicationURL = executableURL
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // Q.app
    }

    func run() -> Never {
        wasConnected = Self.hasCompatibleUSBDevice()
        logger.notice(
            "Q device watcher started; connected=\(self.wasConnected) app=\(self.qApplicationURL.path, privacy: .public)"
        )

        // A Q may already be connected when the user logs in and launchd starts
        // this helper. In that case the app should become available immediately.
        if wasConnected {
            launchQIfNeeded()
        }

        while true {
            Thread.sleep(forTimeInterval: 0.75)
            autoreleasepool {
                let isConnected = Self.hasCompatibleUSBDevice()
                if isConnected && !wasConnected {
                    logger.notice("Compatible Q USB device connected")
                    launchQIfNeeded()
                }
                wasConnected = isConnected
            }
        }
    }

    private func launchQIfNeeded() {
        guard NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.qBundleIdentifier
        ).isEmpty else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: qApplicationURL,
            configuration: configuration
        ) { [logger] _, error in
            if let error {
                logger.error("Could not launch Q: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.notice("Launched Q after USB connection")
            }
        }
    }

    private static func hasCompatibleUSBDevice() -> Bool {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return false }
        let properties = matching as NSMutableDictionary
        properties["idVendor"] = NSNumber(value: espressifVendorID)
        properties["idProduct"] = NSNumber(value: usbSerialJTAGProductID)

        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return false }
        IOObjectRelease(service)
        return true
    }

    private static func absoluteExecutableURL() -> URL {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }
}

QDeviceWatcher().run()
