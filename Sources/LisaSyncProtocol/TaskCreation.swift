// What `task.create` sets (plan §8.2.3): every editable field's first value. R1's defaults are the caller's to fill in
// (normal priority, not splittable); the payload always states all six.

/// The fields of a new task.
public struct TaskCreation: Hashable, Sendable {
    public let title: String
    public let priority: String
    public let deadline: WireDeadline?
    public let estimate: Int64?
    public let splittable: Bool
    public let confirmation: String

    public init(
        title: String, priority: String = "normal", deadline: WireDeadline? = nil, estimate: Int64? = nil,
        splittable: Bool = false, confirmation: String
    ) throws(OperationEnvelopeError) {
        for value: TaskFieldValue in [
            .title(title), .priority(priority), .deadline(deadline), .estimate(estimate), .splittable(splittable),
            .confirmation(confirmation),
        ] {
            _ = try TaskFieldValue(validating: value)
        }
        self.title = title
        self.priority = priority
        self.deadline = deadline
        self.estimate = estimate
        self.splittable = splittable
        self.confirmation = confirmation
    }

    /// Every field with its first value, in `TaskField` order.
    public var fieldValues: [TaskFieldValue] {
        [
            .title(title), .priority(priority), .deadline(deadline), .estimate(estimate), .splittable(splittable),
            .confirmation(confirmation),
        ]
    }
}
