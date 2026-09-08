import Foundation

public struct QEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var source: String
    public var state: QState
    public var priority: Int
    public var timestamp: Date
    public var context: [String: String]
    public var expiresAt: Date?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        source: String,
        state: QState,
        priority: Int,
        timestamp: Date = .now,
        context: [String: String] = [:],
        expiresAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.source = source
        self.state = state
        self.priority = priority
        self.timestamp = timestamp
        self.context = context
        self.expiresAt = expiresAt
        self.isActive = isActive
    }
}
