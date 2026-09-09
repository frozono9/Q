import Foundation

public struct QPomodoroConfiguration: Codable, Equatable, Sendable {
    public static let commonFocusDurations = [15, 25, 30, 45, 60, 90]

    public var focusMinutes: Int
    public var breakMinutes: Int

    public init(focusMinutes: Int = 25, breakMinutes: Int = 5) {
        self.focusMinutes = min(max(focusMinutes, 1), 180)
        self.breakMinutes = min(max(breakMinutes, 1), 60)
    }
}

public enum QAvailabilityControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic
    case manual

    public var name: String {
        switch self {
        case .automatic: "Automatic"
        case .manual: "Manual override"
        }
    }
}

public enum QPomodoroProgress {
    private static let fullBrightness = 0.85
    // A small LED loses apparent presence much faster than its numeric opacity.
    // This ease-out curve keeps it visibly lit through most of its third, while
    // still reaching opal exactly at the boundary.
    private static let visibilityExponent = 0.5

    /// Changes the target duration while preserving time already spent in the phase.
    public static func adjustedRemaining(
        oldTotal: TimeInterval,
        remaining: TimeInterval,
        newTotal: TimeInterval
    ) -> TimeInterval {
        let elapsed = max(0, oldTotal - remaining)
        return max(0, newTotal - elapsed)
    }

    public static func litLEDCount(remainingSeconds: Int, totalSeconds: Int) -> Int {
        guard remainingSeconds > 0, totalSeconds > 0 else { return 0 }

        let scaledRemaining = remainingSeconds * QScene.ledCount
        if scaledRemaining >= totalSeconds * 2 { return 3 }
        if scaledRemaining >= totalSeconds { return 2 }
        return 1
    }

    public static func brightnessLevels(
        remainingSeconds: Int,
        totalSeconds: Int
    ) -> [Double] {
        guard remainingSeconds > 0, totalSeconds > 0 else {
            return Array(repeating: 0, count: QScene.ledCount)
        }

        let remainingFraction = min(
            max(Double(remainingSeconds) / Double(totalSeconds), 0),
            1
        )
        let scaledProgress = remainingFraction * Double(QScene.ledCount)

        return (0..<QScene.ledCount).map { index in
            let segmentLevel = min(max(scaledProgress - Double(index), 0), 1)
            return fullBrightness * pow(segmentLevel, visibilityExponent)
        }
    }

    public static func scene(
        remainingSeconds: Int, totalSeconds: Int, isBreak: Bool = false
    ) -> QScene {
        let brightness = brightnessLevels(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds
        )
        let color: QColor = isBreak ? .green : .purple
        let leds = (0..<QScene.ledCount).map { index in
            QLEDState(
                color: color,
                brightness: brightness[index],
                isEnabled: brightness[index] > 0,
                animation: .solid
            )
        }
        return QScene(name: isBreak ? "Pomodoro Break" : "Pomodoro Focus", leds: leds)
    }
}
