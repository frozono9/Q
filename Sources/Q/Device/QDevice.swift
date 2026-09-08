import Foundation

public enum QButtonEvent: String, Codable, Equatable, Sendable {
    case singlePress
    case doublePress
    case longPress
}

public enum QDeviceError: LocalizedError, Equatable {
    case notConnected
    case invalidLEDIndex(Int)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Q is not connected."
        case .invalidLEDIndex(let index):
            "LED index \(index) is outside the valid range 0...\(QScene.ledCount - 1)."
        }
    }
}

@MainActor
public protocol QDevice: AnyObject {
    var id: String { get }
    var name: String { get }
    var isConnected: Bool { get }
    var currentScene: QScene { get }
    var buttonEvents: AsyncStream<QButtonEvent> { get }

    func connect() async throws
    func disconnect() async
    func apply(scene: QScene) async throws
    func setLED(index: Int, state: QLEDState) async throws
}
