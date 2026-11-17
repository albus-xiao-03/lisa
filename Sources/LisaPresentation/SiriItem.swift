// A task or reminder as Siri and Shortcuts offer it: the host's stable identifier, its title, a detail that tells
// similar items apart, its state and the revision last read.

import Foundation
import LisaAPIContract

/// A task or reminder that an App Intent can act on (SIRI-01). Its identifier is the host's own, so it stays the same
/// across launches and devices; the revision is the one last read, which the action expects.
public struct SiriItem: Hashable, Sendable {
    /// The host's identifier of the task or reminder.
    public var id: String
    /// The title the owner sees.
    public var title: String
    /// What tells this item from others with a similar title, such as its deadline; `nil` when there is nothing to add.
    public var detail: String?
    /// The task's status or the reminder's state, as the host names it.
    public var state: String
    /// The revision last read.
    public var revision: Int64
    /// Whether the action is still possible: an open, started or blocked task; a scheduled, delivered or snoozed
    /// reminder.
    public var isActionable: Bool

    /// An item with every field given.
    public init(id: String, title: String, detail: String?, state: String, revision: Int64, isActionable: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.revision = revision
        self.isActionable = isActionable
    }

    /// The task statuses a task can be completed from.
    public static let completableStatuses: [TaskStatusValue] = [.open, .inProgress, .blocked]
    /// The reminder states a reminder can be snoozed in.
    public static let snoozableStates = ["scheduled", "delivered", "snoozed"]
    /// What a task's detail says when it has no deadline; an open task needs no label.
    private static let statusLabels: [TaskStatusValue: String] = [
        .inProgress: "In progress", .blocked: "Blocked", .completed: "Completed", .cancelled: "Cancelled",
    ]

    /// `task` as an item. Its detail is the deadline, or the status when it is not open.
    public static func task(_ task: TaskDTO, timeZone: TimeZone, locale: Locale) -> SiriItem {
        var detail: String?
        if let deadline = task.deadline {
            if let instant = deadline.instant {
                let zone = deadline.zone.flatMap(TimeZone.init(identifier:)) ?? timeZone
                detail = "Due \(SpokenMoment.dayAndTime(instant, in: zone, locale: locale))"
            } else if let date = deadline.date {
                detail = "Due \(LocalDay.spokenEnglish(date))"
            }
        }
        if detail == nil { detail = statusLabels[task.status] }
        return SiriItem(
            id: task.id, title: task.title, detail: detail, state: task.status.rawValue, revision: task.revision,
            isActionable: completableStatuses.contains(task.status))
    }

    /// `reminder` as an item. Its detail is when it is due, or until when it is snoozed.
    public static func reminder(_ reminder: ReminderDTO, timeZone: TimeZone, locale: Locale) -> SiriItem {
        let detail =
            if reminder.state == "snoozed", let until = reminder.snoozedUntil {
                "Snoozed until \(SpokenMoment.dayAndTime(until, in: timeZone, locale: locale))"
            } else {
                "Due \(SpokenMoment.dayAndTime(reminder.dueAt, in: timeZone, locale: locale))"
            }
        return SiriItem(
            id: reminder.id, title: reminder.title, detail: detail, state: reminder.state,
            revision: reminder.revision, isActionable: snoozableStates.contains(reminder.state))
    }
}
