import Testing
@testable import QCore

@Suite("Virtual Q device")
@MainActor
struct VirtualQDeviceTests {
    @Test func deviceRequiresConnection() async {
        let device = VirtualQDevice()

        do {
            try await device.apply(scene: .working)
            Issue.record("Expected the disconnected device to reject a scene")
        } catch {
            #expect(error as? QDeviceError == .notConnected)
        }
    }

    @Test func applyAndSetLED() async throws {
        let device = VirtualQDevice()
        try await device.connect()

        try await device.apply(scene: .working)
        try await device.setLED(
            index: 0,
            state: QLEDState(color: .green, brightness: 0.5)
        )

        #expect(device.currentScene.name == "Working")
        #expect(device.currentScene.leds[0].color == .green)
        #expect(device.currentScene.leds[0].brightness == 0.5)
    }

    @Test func buttonEventUsesDeviceStream() async {
        let device = VirtualQDevice()
        var iterator = device.buttonEvents.makeAsyncIterator()

        device.sendButtonEvent(.doublePress)

        let event = await iterator.next()
        #expect(event == .doublePress)
    }
}
