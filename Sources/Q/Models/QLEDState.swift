import Foundation

public struct QLEDState: Codable, Equatable, Sendable {
    public var color: QColor
    public var brightness: Double
    public var isEnabled: Bool
    public var animation: QAnimation
    public var animationSpeed: Double
    public var phaseOffset: Double?

    public init(
        color: QColor = .white,
        brightness: Double = 1,
        isEnabled: Bool = true,
        animation: QAnimation = .solid,
        animationSpeed: Double = 1,
        phaseOffset: Double? = nil
    ) {
        self.color = color
        self.brightness = min(max(brightness, 0), 1)
        self.isEnabled = isEnabled
        self.animation = animation
        self.animationSpeed = max(animationSpeed, 0.05)
        self.phaseOffset = phaseOffset
    }

    public static let off = QLEDState(brightness: 0, isEnabled: false)
}
