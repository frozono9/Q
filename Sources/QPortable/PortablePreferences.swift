import Foundation
import QCore

public struct PortablePreferences: Codable, Equatable {
    public var schemaVersion = 1
    public var stateID = "available"
    public var brightness = QAvailability.referenceBrightness
    public var deviceID: String?
    public init() {}

    public func validate() throws {
        guard schemaVersion == 1 else { throw QTransportError.message("Settings belong to an unsupported version. The original file has been preserved.") }
        guard QModeCatalog.availability.states.contains(where: { $0.id == stateID }),
              brightness.isFinite, (0.1...1).contains(brightness),
              deviceID == nil || (deviceID!.hasPrefix("Q-") && deviceID!.count > 2) else {
            throw QTransportError.message("Invalid settings. The original file has been preserved.")
        }
    }
    public var preset: QStatePreset { QModeCatalog.availability.states.first { $0.id == stateID }! }
    public var scene: QScene { QAvailability.scene(preset.scene, brightness: brightness) }
}

public struct PortablePreferencesStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> PortablePreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return PortablePreferences() }
        let value = try JSONDecoder().decode(PortablePreferences.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    public func save(_ value: PortablePreferences) throws {
        try value.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            // Refuse to overwrite a newer/corrupt file introduced since load.
            _ = try load()
            try Data(contentsOf: url).write(to: url.appendingPathExtension("bak"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
