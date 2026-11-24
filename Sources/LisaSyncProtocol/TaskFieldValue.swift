// One task field with its value, as `task.edit` carries it (plan §8.2.3), and the value rules R1 applies: a title of
// 1–200 characters, R1's priorities and confirmations, an estimate of at least one minute, and a deadline or nothing.

/// A task field and its new value.
public enum TaskFieldValue: Hashable, Sendable {
    case title(String)
    /// `low`, `normal`, `high` or `urgent`.
    case priority(String)
    /// `nil` clears the deadline.
    case deadline(WireDeadline?)
    /// Minutes; `nil` clears the estimate.
    case estimate(Int64?)
    case splittable(Bool)
    /// `confirmed`, `possible` or `informational`.
    case confirmation(String)

    public static let maximumTitleCharacters = 200
    public static let priorities: Set<String> = ["low", "normal", "high", "urgent"]
    public static let confirmations: Set<String> = ["confirmed", "possible", "informational"]

    public var field: TaskField {
        switch self {
        case .title: .title
        case .priority: .priority
        case .deadline: .deadline
        case .estimate: .estimate
        case .splittable: .splittable
        case .confirmation: .confirmation
        }
    }

    /// Checks the value rules.
    public init(validating value: TaskFieldValue) throws(OperationEnvelopeError) {
        switch value {
        case .title(let title):
            guard !title.isEmpty, title.count <= Self.maximumTitleCharacters else {
                throw .invalidField("payload.title")
            }
        case .priority(let priority):
            guard Self.priorities.contains(priority) else { throw .invalidField("payload.priority") }
        case .deadline(let deadline):
            if let deadline { _ = try WireDeadline(validating: deadline) }
        case .estimate(let minutes):
            if let minutes, minutes < 1 { throw .invalidField("payload.estimate") }
        case .splittable:
            break
        case .confirmation(let confirmation):
            guard Self.confirmations.contains(confirmation) else { throw .invalidField("payload.confirmation") }
        }
        self = value
    }

    /// The value alone, as it appears under `value` in `task.edit` and under the field's name in `task.create`.
    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .title(let title): .string(title)
            case .priority(let priority): .string(priority)
            case .deadline(let deadline): try deadline?.canonicalValue ?? .null
            case .estimate(let minutes): minutes.map { .integer($0) } ?? .null
            case .splittable(let splittable): .bool(splittable)
            case .confirmation(let confirmation): .string(confirmation)
            }
        }
    }

    /// Reads the value of `field` strictly and checks its rules.
    public init(field: TaskField, canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        let decoded: TaskFieldValue
        switch (field, value) {
        case (.title, .string(let title)): decoded = .title(title)
        case (.priority, .string(let priority)): decoded = .priority(priority)
        case (.deadline, .null): decoded = .deadline(nil)
        case (.deadline, .object): decoded = .deadline(try WireDeadline(canonicalValue: value))
        case (.estimate, .null): decoded = .estimate(nil)
        case (.estimate, .integer(let minutes)): decoded = .estimate(minutes)
        case (.splittable, .bool(let splittable)): decoded = .splittable(splittable)
        case (.confirmation, .string(let confirmation)): decoded = .confirmation(confirmation)
        default: throw .invalidField("payload.\(field.rawValue)")
        }
        try self.init(validating: decoded)
    }
}
