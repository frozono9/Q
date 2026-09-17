import Foundation
import QCore
import QPortable
import QSerialNative
#if os(Windows)
import WinSDK
#else
import Glibc
#endif

@main
struct QCommand {
    static func message(_ text: String) {
        try? FileHandle.standardError.write(contentsOf: Data((text + "\n").utf8))
    }

    static func json(_ values: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) {
            // A watch piped to another process must deliver each event now,
            // rather than waiting for stdio's buffer to fill or the CLI to exit.
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
    }

    static func hold(_ client: QClient, seconds: Double?) {
        let end = seconds.map { ProcessInfo.processInfo.systemUptime + $0 }
        while q_interrupted() == 0 && (end == nil || ProcessInfo.processInfo.systemUptime < end!) {
            client.poll()
            if client.session == nil { Thread.sleep(forTimeInterval: 0.1) }
        }
    }

    static func run() throws {
        var options = try CLIOptions(Array(CommandLine.arguments.dropFirst()))
        if options.command == .help { print(CLIOptions.help); return }
        if options.command == .list {
            let ports = try NativeSerialIO.candidates()
            json(["candidates": ports]); return
        }
        q_install_interrupt_handler()
        let client = QClient(selection: options.selection)
        client.onConnection = { message($0) }
        client.onButton = { json(["event": "button", "gesture": $0.rawValue]) }
        defer {
            if client.scene != nil, client.session != nil {
                do { try client.apply(.idle) }
                catch { message("Could not confirm LEDs off: \(error.localizedDescription)") }
            }
            client.close()
        }
        try client.connect()
        guard let session = client.session, let info = session.info else { throw QTransportError.message("No identity") }
        if options.command == .status {
            json(["connected": true, "port": session.path, "id": info.deviceIdentifier ?? "",
                  "firmware": info.firmwareVersion ?? "", "protocol": info.protocolVersion])
            return
        }
        if options.command == .watch { hold(client, seconds: options.seconds); return }
        // Let firmware's three green confirmation pulses finish first.
        hold(client, seconds: 2.2)
        if q_interrupted() != 0 { return }
        if options.command == .test {
            for color in ["red", "green", "blue", "white", "traffic"] {
                if q_interrupted() != 0 { break }
                options.color = color
                try client.apply(options.scene())
                message("Scene accepted: \(color)")
                hold(client, seconds: 3)
            }
        } else {
            try client.apply(options.command == .off ? .idle : options.scene())
            message("Scene accepted. Press Ctrl+C to finish.")
            hold(client, seconds: options.seconds)
        }
    }

    static func main() {
        do { try run() }
        catch {
            message("q: \(error.localizedDescription)")
            #if os(Windows)
            ExitProcess(1)
            #else
            exit(1)
            #endif
        }
    }
}
