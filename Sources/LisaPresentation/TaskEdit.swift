// Changes the owner makes to a task's details on the tasks screen; unset fields stay unchanged.

import Foundation
import LisaAPIContract

/// Changes to a task's details (UI-02). Fields left `nil` stay unchanged on the host.
public struct TaskEdit: Hashable, Sendable {
    /// A new title.
    public var title: String?
    /// New notes.
    public var notes: String?
    /// A new priority.
    public var priority: TaskPriorityValue?
    /// A new deadline.
    public var deadline: DeadlineDTO?
    /// Whether to remove the deadline.
    public var clearDeadline: Bool
    /// A new estimate in minutes.
    public var estimatedMinutes: Int?

    /// An edit setting the given fields.
    public init(
        title: String? = nil, notes: String? = nil, priority: TaskPriorityValue? = nil, deadline: DeadlineDTO? = nil,
        clearDeadline: Bool = false, estimatedMinutes: Int? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.deadline = deadline
        self.clearDeadline = clearDeadline
        self.estimatedMinutes = estimatedMinutes
    }

    /// Whether the edit changes nothing.
    public var isEmpty: Bool {
        title == nil && notes == nil && priority == nil && deadline == nil && !clearDeadline && estimatedMinutes == nil
    }

    /// Why the edit cannot be sent, or `nil` when it can.
    public var problem: String? {
        if isEmpty { return "Nothing was changed." }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A task needs a title." }
        if let deadline, !deadline.isValid { return "The deadline is not a valid date or time." }
        if deadline != nil, clearDeadline { return "Choose either a new deadline or no deadline." }
        if let estimatedMinutes, estimatedMinutes <= 0 { return "The estimate must be at least one minute." }
        return nil
    }

    /// The patch for a task the owner last saw at `expectedRevision`.
    func patch(expectedRevision: Int64) -> TaskPatchRequest {
        TaskPatchRequest(
            expectedRevision: expectedRevision, title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes, priority: priority, deadline: deadline, clearDeadline: clearDeadline ? true : nil,
            estimatedMinutes: estimatedMinutes)
    }
}
