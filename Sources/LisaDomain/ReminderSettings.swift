// Reminder timing and quiet-hour policy (REM-02 starting values, visible and editable).

import Foundation
import LisaTime

/// Reminder policy settings. These are R1 starting values, not established personal preferences.
public struct ReminderSettings: Hashable, Codable, Sendable {
    /// Minutes before a timed deadline at which reminders are due.
    public var deadlineOffsetsMinutes: [Int]
    /// Date-only deadlines are reminded only when a reminder time is configured; their meaning stays date-only.
    public var dateOnlyReminderTime: LocalTime?
    /// Local time of the at-most-daily overdue reminder.
    public var overdueReminderTime: LocalTime
    /// Local time of the at-most-daily follow-up for each unresolved event proposal.
    public var proposalFollowUpTime: LocalTime
    /// Minutes before an accepted plan block starts.
    public var planBlockLeadMinutes: Int
    public var notifyCommitmentChanges: Bool
    public var snoozeMinutes: Int
    public var quietHours: QuietHours
    /// Also send reminders by email to the approved addresses (notifications remain the default channel).
    public var emailReminders: Bool

    public init(
        deadlineOffsetsMinutes: [Int] = [1440, 60], dateOnlyReminderTime: LocalTime? = nil,
        overdueReminderTime: LocalTime = LocalTime(secondsSinceMidnight: 9 * 3600),
        proposalFollowUpTime: LocalTime = LocalTime(secondsSinceMidnight: 9 * 3600), planBlockLeadMinutes: Int = 10,
        notifyCommitmentChanges: Bool = true, snoozeMinutes: Int = 15, quietHours: QuietHours = .defaultValue,
        emailReminders: Bool = false
    ) {
        self.deadlineOffsetsMinutes = deadlineOffsetsMinutes
        self.dateOnlyReminderTime = dateOnlyReminderTime
        self.overdueReminderTime = overdueReminderTime
        self.proposalFollowUpTime = proposalFollowUpTime
        self.planBlockLeadMinutes = planBlockLeadMinutes
        self.notifyCommitmentChanges = notifyCommitmentChanges
        self.snoozeMinutes = snoozeMinutes
        self.quietHours = quietHours
        self.emailReminders = emailReminders
    }
}
