import Foundation

public struct QMeetingHoldLifecycle: Sendable {
    public struct Hold: Equatable, Sendable {
        public var id: UUID
        public var provider: QMeetingProvider

        public init(id: UUID = UUID(), provider: QMeetingProvider) {
            self.id = id
            self.provider = provider
        }
    }

    public private(set) var active: Hold?

    public init() {}

    public mutating func begin(provider: QMeetingProvider, id: UUID = UUID()) -> Hold? {
        guard active == nil else { return nil }
        let hold = Hold(id: id, provider: provider)
        active = hold
        return hold
    }

    public func isCurrent(_ hold: Hold) -> Bool {
        active == hold
    }

    public mutating func end() -> Hold? {
        defer { active = nil }
        return active
    }
}
