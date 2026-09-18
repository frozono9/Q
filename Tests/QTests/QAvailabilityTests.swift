import Testing
@testable import QCore

@Test func availabilityButtonMatchesMacCatalog() {
    #expect(QAvailability.stateAfterPress("available") == "focus")
    #expect(QAvailability.stateAfterPress("focus") == "busy")
    #expect(QAvailability.stateAfterPress("busy") == "available")
    #expect(QAvailability.stateAfterPress("away") == "available")
    #expect(QAvailability.stateAfterPress("offline") == "available")
    #expect(QAvailability.nextPrimaryStateID(after: "away") == nil)
}

@Test func brightnessAlwaysRendersFromBaseScene() {
    let base = QModeCatalog.availability.defaultState!.scene
    #expect(QAvailability.scene(base, brightness: 0.5).leds[0].brightness == 0.5)
    #expect(QAvailability.scene(base, brightness: 1).leds[0].brightness == 1)
    #expect(base.leds[0].brightness == 0.85)
    #expect(QAvailability.scene(.idle, brightness: 1).leds.allSatisfy { !$0.isEnabled })
}
