// The task fields an owner edits one at a time (plan §8.2.3: title, priority, deadline or clear, estimate, splittable,
// confirmation). Each is its own register when merged (plan §8.3.1).

/// An editable task field.
public enum TaskField: String, Hashable, Sendable, CaseIterable {
    case title
    case priority
    case deadline
    case estimate
    case splittable
    case confirmation
}
