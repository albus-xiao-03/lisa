// What a task shows after merging (plan §8.3.1): each field's surviving values (two or more of the winning authority
// class are a conflict), the notes in display order, the tags, the terminal status and whether a deletion dominates.

import LisaSyncProtocol

/// A merged task, ready to display.
public struct TaskView: Hashable, Sendable {
    /// Whether the task's creation has been applied.
    public let exists: Bool
    public let title: [String]
    public let priority: [String]
    public let deadline: [WireDeadline?]
    public let estimate: [Int64?]
    public let splittable: [Bool]
    public let confirmation: [String]
    public let notes: [String]
    /// Sorted by Unicode scalar order.
    public let tags: [String]
    public let status: TerminalActions.Status
    public let isDeleted: Bool
    /// The edits a deletion supersedes; kept for display while retention allows.
    public let supersededByDeletion: Set<Identifier128>

    public init(
        exists: Bool, title: [String], priority: [String], deadline: [WireDeadline?], estimate: [Int64?],
        splittable: [Bool], confirmation: [String], notes: [String], tags: [String], status: TerminalActions.Status,
        isDeleted: Bool, supersededByDeletion: Set<Identifier128>
    ) {
        self.exists = exists
        self.title = title
        self.priority = priority
        self.deadline = deadline
        self.estimate = estimate
        self.splittable = splittable
        self.confirmation = confirmation
        self.notes = notes
        self.tags = tags
        self.status = status
        self.isDeleted = isDeleted
        self.supersededByDeletion = supersededByDeletion
    }

    /// The fields with two or more surviving values.
    public var conflicts: Set<TaskField> {
        var fields: Set<TaskField> = []
        if title.count > 1 { fields.insert(.title) }
        if priority.count > 1 { fields.insert(.priority) }
        if deadline.count > 1 { fields.insert(.deadline) }
        if estimate.count > 1 { fields.insert(.estimate) }
        if splittable.count > 1 { fields.insert(.splittable) }
        if confirmation.count > 1 { fields.insert(.confirmation) }
        return fields
    }
}
