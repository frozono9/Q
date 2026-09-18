import Foundation
import Testing
@testable import QPortable

@Test func preferencesSurviveReplacementAndKeepBackup() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = PortablePreferencesStore(url: dir.appendingPathComponent("settings.json"))
    var value = try store.load()
    value.stateID = "busy"; value.brightness = 0.4; value.deviceID = "Q-TEST"
    try store.save(value)
    #expect(try store.load() == value)
    value.stateID = "away"
    try store.save(value)
    #expect(try store.load() == value)
    let backup = try JSONDecoder().decode(PortablePreferences.self, from: Data(contentsOf: store.url.appendingPathExtension("bak")))
    #expect(backup.stateID == "busy")
}

@Test func newerOrInvalidSettingsAreNeverOverwritten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = PortablePreferencesStore(url: dir.appendingPathComponent("settings.json"))
    for original in ["{\"schemaVersion\":99,\"stateID\":\"available\",\"brightness\":0.5}", "broken"] {
        try Data(original.utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(PortablePreferences()) }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == original)
    }
    var value = PortablePreferences(); value.brightness = .nan
    #expect(throws: (any Error).self) { try value.validate() }
}
