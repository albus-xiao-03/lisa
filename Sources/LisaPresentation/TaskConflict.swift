// A task change the host refused because the task changed meanwhile, with the change and the current task.

import Foundation
import LisaAPIContract

/// A task change the host refused because the task changed since the owner saw it (UI-03). The screen shows the
/// current task next to the refused change; the owner applies the change again to the current version or discards it.
public struct TaskConflict: Hashable, Sendable {
    /// The task's identifier.
    public var taskID: String
    /// The refused action, with its queued entry and the task's current revision.
    public var conflict: ActionConflict
    /// The change that was refused.
    public var change: TaskPatchRequest?
    /// The task as the host has it now, once it could be fetched.
    public var current: TaskDTO?

    /// A conflict on `taskID`.
    public init(taskID: String, conflict: ActionConflict, change: TaskPatchRequest?, current: TaskDTO?) {
        self.taskID = taskID
        self.conflict = conflict
        self.change = change
        self.current = current
    }
}
