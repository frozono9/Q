import Foundation

public enum QRuleTrigger: Codable, Equatable, Sendable {
    case webhook(path: String)
    case application(bundleIdentifier: String)
    case event(source: String, name: String)
    case shortcut(name: String)
}

public enum QConditionOperator: String, Codable, CaseIterable, Sendable {
    case equals
    case notEquals
    case contains
    case exists
}

public struct QRuleCondition: Codable, Equatable, Sendable {
    public var field: String
    public var operation: QConditionOperator
    public var value: String?

    public init(field: String, operation: QConditionOperator, value: String? = nil) {
        self.field = field
        self.operation = operation
        self.value = value
    }
}

public struct QCustomRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var trigger: QRuleTrigger
    public var conditions: [QRuleCondition]
    public var sceneID: UUID
    public var priority: Int
    public var buttonMapping: QButtonMapping

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: QRuleTrigger,
        conditions: [QRuleCondition] = [],
        sceneID: UUID,
        priority: Int,
        buttonMapping: QButtonMapping = QButtonMapping()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.conditions = conditions
        self.sceneID = sceneID
        self.priority = min(max(priority, 0), 100)
        self.buttonMapping = buttonMapping
    }
}
