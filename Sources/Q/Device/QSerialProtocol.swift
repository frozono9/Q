import Foundation

/// Q's deliberately small, line-oriented USB protocol. Keeping the framing
/// independent from JSON makes it easy to inspect in a serial terminal and
/// cheap to parse on the XIAO ESP32-C3.
public enum QSerialProtocol {
    public static let version = 1

    public static func sceneCommand(_ scene: QScene) -> Data {
        let leds = scene.leds.map { led in
            [
                byte(led.color.red),
                byte(led.color.green),
                byte(led.color.blue),
                byte(led.brightness),
                led.isEnabled ? "1" : "0",
                String(animationCode(led.animation)),
                String(Int((led.animationSpeed * 1_000).rounded())),
                String(Int(((led.phaseOffset ?? 0) * 1_000).rounded()))
            ].joined(separator: ",")
        }
        return Data(("S|" + leds.joined(separator: "|") + "\n").utf8)
    }

    public static func buttonEvent(from line: String) -> QButtonEvent? {
        switch line.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "B|single": .singlePress
        case "B|double": .doublePress
        case "B|long": .longPress
        default: nil
        }
    }

    private static func byte(_ value: Double) -> String {
        String(Int((min(max(value, 0), 1) * 255).rounded()))
    }

    private static func animationCode(_ animation: QAnimation) -> Int {
        switch animation {
        case .solid: 0
        case .blink: 1
        case .pulse: 2
        case .flash: 3
        case .flashThenSolid: 4
        case .fadeInOut: 5
        case .chaseUp: 6
        case .chaseDown: 7
        case .bounce: 8
        case .progress: 9
        case .alternating: 10
        case .gradientShift: 11
        case .rainbow: 12
        }
    }
}
