// The deterministic urgency rule behind Time Sensitive notifications (owner opt-in) and call eligibility.

import Foundation
import LisaDomain

/// Decides urgency from confirmed facts only; a model calling something "urgent" never counts (CALL-01).
public enum UrgencyRule {
    /// A confirmed, high-priority, incomplete task whose timed deadline is within `windowMinutes`.
    public static func isUrgentDeadline(_ task: LisaTask, now: Date, windowMinutes: Int) -> Bool {
        guard task.isConfirmedCommitment, task.status.isActive, task.priority.isHigh,
            case .at(let instant, _) = task.deadline
        else { return false }
        let remaining = instant.timeIntervalSince(now)
        return remaining > 0 && remaining <= TimeInterval(windowMinutes * 60)
    }

    /// The interruption level for a notification. Only reminders and overdue notices about urgent deadlines can be
    /// Time Sensitive, and only with the owner's opt-in. Everything else uses the standard level.
    public static func interruptionLevel(
        category: NotificationCategory, task: LisaTask?, now: Date, settings: NotificationSettings
    ) -> InterruptionLevel {
        guard settings.timeSensitiveForUrgentDeadlines, category == .reminder, let task,
            isUrgentDeadline(task, now: now, windowMinutes: settings.urgentDeadlineWindowMinutes)
        else { return .active }
        return .timeSensitive
    }
}
