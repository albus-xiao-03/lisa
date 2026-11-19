// The task-edit sheet's fields, started from the task shown, and the edit that carries only the fields the owner
// changed.

import Foundation
import LisaAPIContract
import LisaPresentation

/// The fields of the task-edit sheet. Only the fields the owner changed are sent, so a field left alone is never
/// recorded as corrected by the owner on the host.
///
/// - The deadline is kept, removed, or replaced by a day, or a day and a time, picked in `zone`: the owner's zone, which
///   the sheet's date picker shows (`PickedDeadline`). A new deadline equal to the current one is not sent.
/// - An estimate can be set or changed but not removed: the host's task patch (`TaskPatchRequest`) has no way to remove
///   one.
struct TaskEditForm: Hashable {
    /// What happens to the task's deadline.
    enum DeadlineChoice: Hashable {
        /// It stays as it is.
        case keep
        /// It is removed.
        case remove
        /// It becomes the day, or the day and time, picked.
        case set
    }

    var title: String
    var notes: String
    var priority: TaskPriorityValue
    var hasEstimate: Bool
    var estimatedMinutes: Int
    var deadlineChoice = DeadlineChoice.keep
    /// The day, or day and time, picked for a new deadline, as the date picker holds it.
    var deadlineDate: Date
    /// Whether a new deadline has a time of day.
    var deadlineIncludesTime: Bool
    /// The zone the date picker shows and a new deadline is built in.
    let zone: TimeZone

    /// The fields of `task` as shown. The date picker shows `zone` and starts at the task's deadline, or at `now`.
    init(task: TaskDTO, zone: TimeZone = .current, now: Date = Date()) {
        title = task.title
        notes = task.notes
        priority = task.priority
        hasEstimate = task.estimatedMinutes != nil
        estimatedMinutes = task.estimatedMinutes ?? 30
        deadlineDate = PickedDeadline.pickerValue(for: task.deadline, in: zone, now: now)
        deadlineIncludesTime = task.deadline?.instant != nil
        self.zone = zone
    }

    /// The new deadline picked, while the owner chose to set one.
    var pickedDeadline: DeadlineDTO? {
        guard deadlineChoice == .set else { return nil }
        return PickedDeadline.deadline(deadlineDate, includesTime: deadlineIncludesTime, in: zone)
    }

    /// The edit of `task` with the fields that differ from it; `TaskEdit.problem` says when nothing changed.
    func edit(of task: TaskDTO) -> TaskEdit {
        TaskEdit(
            title: title == task.title ? nil : title,
            notes: notes == task.notes ? nil : notes,
            priority: priority == task.priority ? nil : priority,
            deadline: pickedDeadline == task.deadline ? nil : pickedDeadline,
            clearDeadline: deadlineChoice == .remove && task.deadline != nil,
            estimatedMinutes: hasEstimate && estimatedMinutes != task.estimatedMinutes ? estimatedMinutes : nil)
    }
}
