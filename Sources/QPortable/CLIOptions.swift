import Foundation
import QCore

public struct CLIOptions {
    public enum Command: String { case help, list, status, lights, off, watch, test, serve }
    public let command: Command
    public var selection = QSelection()
    public var seconds: Double?
    public var brightness = 0.7
    public var color = "white"
    public var settingsPath: String?

    public init(_ arguments: [String]) throws {
        guard let first = arguments.first else { command = .help; return }
        if first == "--help" || first == "-h" { command = .help; return }
        guard let command = Command(rawValue: first) else { throw QTransportError.message("Unknown command: \(first). Use q --help.") }
        self.command = command
        var rest = Array(arguments.dropFirst())
        if command == .lights, let first = rest.first, !first.hasPrefix("--") { color = rest.removeFirst() }
        var seen = Set<String>()
        while !rest.isEmpty {
            let flag = rest.removeFirst()
            guard ["--port", "--id", "--seconds", "--brightness", "--settings"].contains(flag), seen.insert(flag).inserted,
                  !rest.isEmpty else { throw QTransportError.message("Unknown, repeated or incomplete option: \(flag)") }
            let value = rest.removeFirst()
            switch flag {
            case "--settings":
                guard command == .serve, !value.isEmpty else { throw QTransportError.message("--settings is required for serve only") }
                settingsPath = value
            case "--port":
                guard !value.isEmpty else { throw QTransportError.message("Port must not be empty") }
                selection.port = value
            case "--id":
                guard value.hasPrefix("Q-"), value.count > 2 else { throw QTransportError.message("Expected a device ID starting with Q-") }
                selection.deviceID = value
            case "--seconds":
                guard [.lights, .off, .watch].contains(command), let number = Double(value), number.isFinite, number > 0, number <= 86400 else {
                    throw QTransportError.message("--seconds must be 0 < seconds <= 86400, for lights/off/watch")
                }
                seconds = number
            case "--brightness":
                guard [.lights, .test].contains(command), let number = Double(value), number.isFinite, (0...1).contains(number) else {
                    throw QTransportError.message("--brightness must be 0...1, for lights/test")
                }
                brightness = number
            default: break
            }
        }
        guard command != .list || seen.isEmpty, command != .help || seen.isEmpty else {
            throw QTransportError.message("This command does not take options")
        }
        if command == .lights { _ = try scene() }
        if command == .serve, settingsPath == nil { throw QTransportError.message("serve requires --settings <absolute file path>") }
    }

    public func scene() throws -> QScene {
        func led(_ r: Double, _ g: Double, _ b: Double, animation: QAnimation = .solid, phase: Double = 0) -> QLEDState {
            QLEDState(color: QColor(red: r, green: g, blue: b), brightness: brightness,
                      animation: animation, animationSpeed: animation == .rainbow ? 0.1 : 1, phaseOffset: phase)
        }
        let state: QLEDState
        switch color.lowercased() {
        case "red": state = led(1, 0, 0)
        case "green": state = led(0, 1, 0)
        case "blue": state = led(0, 0, 1)
        case "yellow": state = led(1, 1, 0)
        case "white": state = led(1, 1, 1)
        case "traffic": return QScene(name: "Traffic light", leds: [led(1, 0, 0), led(1, 0.75, 0), led(0, 1, 0)])
        case "rainbow": return QScene(name: "Rainbow", leds: (0..<3).map { led(1, 1, 1, animation: .rainbow, phase: Double($0) / 3) })
        default: throw QTransportError.message("Unknown color: \(color). Choose red, green, blue, yellow, white, traffic or rainbow.")
        }
        return QScene(name: color.capitalized, leds: Array(repeating: state, count: 3))
    }

    public static let help = """
    Q portable CLI (experimental, protocol 1)

      q list                         List USB candidates (does not open them)
      q status [--port COM9]          Identify Q and print JSON
      q lights traffic --seconds 10  Set a scene, then turn LEDs off
      q lights rainbow              Keep the scene until Ctrl+C
      q off                         Keep LEDs off until Ctrl+C
      q watch [--seconds 30]         Print physical button events as JSON
      q test                        Red, green, blue, white and traffic test
      q serve --settings <path>     Desktop client JSON-lines session (IPC v1)

    Selection: --port COM9 (Windows) or /dev/ttyACM0 (Linux), --id Q-...
    Brightness: --brightness 0...1 for lights/test (default 0.7).
    lights/off/watch run until Ctrl+C unless --seconds is supplied.
    Reconnection follows the same device ID even if its port changes.
    Opening Q starts its green handshake pulses. When the CLI exits, firmware
    may return to its red waiting pulse after its heartbeat timeout.
    """
}
