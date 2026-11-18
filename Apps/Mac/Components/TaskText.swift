// Words for a task's status, priority and deadline, as the Mac app's screens show them.

import Foundation
import LisaAPIContract

/// Display words for task and idea values.
enum TaskText {
    /// The status in words.
    static func status(_ status: TaskStatusValue) -> String {
        switch status {
        case .open: "Open"
        case .inProgress: "In progress"
        case .blocked: "Blocked"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }

    /// The priority in words.
    static func priority(_ priority: TaskPriorityValue) -> String {
        switch priority {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    /// The deadline in words: its date, or its date and time on this Mac's clock.
    static func deadline(_ deadline: DeadlineDTO) -> String {
        if let instant = deadline.instant { return instant.formatted(date: .abbreviated, time: .shortened) }
        if let date = deadline.date { return LocalDayText.words(for: date, style: .abbreviated) }
        return "Not set"
    }
}
