import Foundation

public enum QDiagnosticOutcome: String, Codable, Sendable {
    case information
    case confirmed
    case unconfirmed
    case failed
}

public struct QDiagnosticEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var category: String
    public var title: String
    public var detail: String
    public var outcome: QDiagnosticOutcome

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        category: String,
        title: String,
        detail: String = "",
        outcome: QDiagnosticOutcome = .information
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.detail = detail
        self.outcome = outcome
    }
}

public struct QDiagnosticTimeline: Sendable {
    public let capacity: Int
    public private(set) var events: [QDiagnosticEvent] = []

    public init(capacity: Int = 20) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ event: QDiagnosticEvent) {
        events.insert(event, at: 0)
        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }
    }
}
