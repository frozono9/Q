import Foundation

public struct QScene: Codable, Equatable, Identifiable, Sendable {
    public static let ledCount = 3

    public var id: UUID
    public var name: String
    public var leds: [QLEDState]

    public init(id: UUID = UUID(), name: String, leds: [QLEDState]) {
        self.id = id
        self.name = name
        self.leds = Array(leds.prefix(Self.ledCount))
        while self.leds.count < Self.ledCount {
            self.leds.append(.off)
        }
    }

    public static let idle = QScene(name: "Idle", leds: [.off, .off, .off])

    public static let working = QScene(
        name: "Working",
        leds: Array(
            repeating: QLEDState(color: .amber, brightness: 0.7, animation: .chaseUp),
            count: ledCount
        )
    )

    public static let needsAttention = QScene(
        name: "Needs Attention",
        leds: Array(
            repeating: QLEDState(color: .blue, brightness: 0.85, animation: .fadeInOut),
            count: ledCount
        )
    )
}
