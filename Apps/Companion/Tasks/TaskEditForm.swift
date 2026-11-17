// The task-edit sheet's fields, started from the task shown, and the edit that carries only the fields the owner
// changed.

import LisaAPIContract
import LisaPresentation

/// The fields of the task-edit sheet. Only the fields the owner changed are sent, so a field left alone is never
/// recorded as corrected by the owner on the host. An estimate can be set or changed but not removed, because
/// `TaskEdit` cannot remove one; a deadline can only be removed here.
struct TaskEditForm: Hashable {
    var title: String
    var notes: String
    var priority: TaskPriorityValue
    var hasEstimate: Bool
    var estimatedMinutes: Int
    var removesDeadline = false

    /// The fields of `task` as shown.
    init(task: TaskDTO) {
        title = task.title
        notes = task.notes
        priority = task.priority
        hasEstimate = task.estimatedMinutes != nil
        estimatedMinutes = task.estimatedMinutes ?? 30
    }

    /// The edit of `task` with the fields that differ from it; `TaskEdit.problem` says when nothing changed.
    func edit(of task: TaskDTO) -> TaskEdit {
        TaskEdit(
            title: title == task.title ? nil : title,
            notes: notes == task.notes ? nil : notes,
            priority: priority == task.priority ? nil : priority,
            clearDeadline: removesDeadline && task.deadline != nil,
            estimatedMinutes: hasEstimate && estimatedMinutes != task.estimatedMinutes ? estimatedMinutes : nil)
    }
}
