import Foundation

/// Shared availability behavior. The Mac and portable clients use the same
/// factory catalog, primary cycle and non-cumulative brightness transform.
public enum QAvailability {
    public static let referenceBrightness = 0.85
    public static func nextPrimaryStateID(after id: String) -> String? {
        let cycle = ["available", "focus", "busy"]
        guard let index = cycle.firstIndex(of: id) else { return nil }
        return cycle[(index + 1) % cycle.count]
    }

    public static func stateAfterPress(_ id: String) -> String {
        guard let preset = QModeCatalog.availability.states.first(where: { $0.id == id }) else { return id }
        switch QModeCatalog.availability.buttonMapping(for: preset.state).singlePress {
        case .cycleScene: return nextPrimaryStateID(after: id) ?? id
        case .setState(let state):
            return QModeCatalog.availability.states.first(where: { $0.state == state })?.id ?? id
        default: return id
        }
    }

    public static func scene(_ scene: QScene, brightness: Double) -> QScene {
        let gain = brightness / referenceBrightness
        var adjusted = scene
        adjusted.leds = scene.leds.map { led in
            var value = led
            value.brightness = min(led.brightness * gain, 1)
            return value
        }
        return adjusted
    }
}
