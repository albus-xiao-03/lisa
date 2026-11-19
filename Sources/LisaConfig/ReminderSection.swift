// The `reminders` section: deadline offsets, daily reminder times, snooze, quiet hours and the email channel.

import LisaDomain
import LisaTime

/// Decodes `reminders` into the reminder policy (REM-01, REM-02). Absent settings keep the R1 starting values of
/// `ReminderSettings()`: 24 hours and 1 hour before timed deadlines, no reminder for date-only deadlines until a time
/// is set, overdue and proposal follow-ups at 09:00, 10 minutes before plan blocks, change notices on, 15-minute
/// snooze, quiet hours 22:00–07:00, and no reminder emails.
enum ReminderSection {
    static func decode(_ section: ConfigSection?) -> ReminderSettings {
        let defaults = ReminderSettings()
        guard let section else { return defaults }
        defer { section.finish() }
        let offsets = section.integerList(
            "deadlineOffsetsMinutes", default: defaults.deadlineOffsetsMinutes, maxCount: 10, in: 1...10_080)
        return ReminderSettings(
            deadlineOffsetsMinutes: Array(Set(offsets)).sorted(by: >),
            dateOnlyReminderTime: section.optionalTime("dateOnlyReminderTime"),
            overdueReminderTime: section.time("overdueReminderTime", default: defaults.overdueReminderTime),
            proposalFollowUpTime: section.time("proposalFollowUpTime", default: defaults.proposalFollowUpTime),
            planBlockLeadMinutes: section.integer(
                "planBlockLeadMinutes", default: defaults.planBlockLeadMinutes, in: 0...240),
            notifyCommitmentChanges: section.bool("notifyCommitmentChanges", default: defaults.notifyCommitmentChanges),
            snoozeMinutes: section.integer("snoozeMinutes", default: defaults.snoozeMinutes, in: 1...1440),
            quietHours: quietHours(section.section("quietHours"), default: defaults.quietHours),
            emailReminders: section.bool("emailReminders", default: defaults.emailReminders))
    }

    /// `{ start: "22:00", end: "07:00" }`, which may wrap past midnight; equal times mean no quiet hours.
    private static func quietHours(_ section: ConfigSection?, default fallback: QuietHours) -> QuietHours {
        guard let section else { return fallback }
        defer { section.finish() }
        return QuietHours(
            start: section.time("start", default: fallback.start), end: section.time("end", default: fallback.end))
    }
}
