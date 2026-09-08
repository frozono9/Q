import Foundation

public enum QAnimation: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid
    case blink
    case pulse
    case flash
    case fadeInOut
    case chaseUp
    case chaseDown
    case bounce
    case progress
    case alternating
    case gradientShift
    case rainbow

    public var id: String { rawValue }
}
