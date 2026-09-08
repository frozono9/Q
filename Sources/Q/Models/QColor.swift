import Foundation

public struct QColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
    }

    public init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((rgb >> 16) & 0xff) / 255,
            green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255
        )
    }

    public var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    public static let red = QColor(red: 1, green: 0.12, blue: 0.12)
    public static let amber = QColor(red: 1, green: 0.5, blue: 0.04)
    public static let green = QColor(red: 0.15, green: 0.9, blue: 0.35)
    public static let blue = QColor(red: 0.12, green: 0.48, blue: 1)
    public static let purple = QColor(red: 0.62, green: 0.3, blue: 1)
    public static let white = QColor(red: 1, green: 1, blue: 1)
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
