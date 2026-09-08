import Combine
import Foundation
import OSLog

@MainActor
public final class VirtualQDevice: ObservableObject, QDevice {
    public let id = "virtual-q"
    public let name = "Virtual Q"

    @Published public private(set) var isConnected = false
    @Published public private(set) var currentScene: QScene = .idle
    @Published public private(set) var sceneAppliedAt = Date.now
    @Published public private(set) var lastButtonEvent: QButtonEvent?

    public let buttonEvents: AsyncStream<QButtonEvent>

    private let buttonContinuation: AsyncStream<QButtonEvent>.Continuation
    private let logger = Logger(subsystem: "app.q", category: "virtual-device")

    public init() {
        let stream = AsyncStream<QButtonEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        buttonEvents = stream.stream
        buttonContinuation = stream.continuation
    }

    deinit {
        buttonContinuation.finish()
    }

    public func connect() async throws {
        isConnected = true
        logger.info("Virtual Q connected")
    }

    public func disconnect() async {
        isConnected = false
        logger.info("Virtual Q disconnected")
    }

    public func apply(scene: QScene) async throws {
        guard isConnected else { throw QDeviceError.notConnected }
        currentScene = scene
        sceneAppliedAt = .now
        logger.debug("Applied scene: \(scene.name, privacy: .public)")
    }

    public func setLED(index: Int, state: QLEDState) async throws {
        guard isConnected else { throw QDeviceError.notConnected }
        guard currentScene.leds.indices.contains(index) else {
            throw QDeviceError.invalidLEDIndex(index)
        }
        currentScene.leds[index] = state
        sceneAppliedAt = .now
        logger.debug("Updated virtual LED \(index)")
    }

    public func sendButtonEvent(_ event: QButtonEvent) {
        lastButtonEvent = event
        buttonContinuation.yield(event)
        logger.debug("Virtual button: \(event.rawValue, privacy: .public)")
    }
}
