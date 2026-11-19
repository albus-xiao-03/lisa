// REM-04: what happens to reminders and briefs that came due while the host was unavailable.

import Foundation
import LisaDomain

/// A reminder that came due during downtime.
public struct MissedReminder: Hashable, Sendable {
    public var id: ReminderID
    public var rule: ReminderRule
    public var dueAt: Date
    /// The subject was resolved or changed during the downtime.
    public var obsolete: Bool
    /// For deadline reminders: whether the deadline itself has passed.
    public var deadlinePassed: Bool

    public init(id: ReminderID, rule: ReminderRule, dueAt: Date, obsolete: Bool, deadlinePassed: Bool) {
        self.id = id
        self.rule = rule
        self.dueAt = dueAt
        self.obsolete = obsolete
        self.deadlinePassed = deadlinePassed
    }
}

/// The recovery decision for one missed reminder, with the reason recorded for the owner.
public struct RecoveryDecision: Hashable, Sendable {
    public var id: ReminderID
    public var deliver: Bool
    public var reason: String
}

/// Recovery rules.
public enum RecoveryPolicy {
    /// Suppresses obsolete reminders, drops deadline reminders whose deadline passed (the overdue reminder takes
    /// over), and coalesces missed low-priority reminders so that only the latest of each rule is delivered.
    public static func decide(_ missed: [MissedReminder]) -> [RecoveryDecision] {
        var decisions: [RecoveryDecision] = []
        let lowPriority: Set<ReminderRule> = [.proposalFollowUp, .planBlockStart, .overdue]
        var latestLowPriority: [ReminderRule: MissedReminder] = [:]
        for reminder in missed.sorted(by: { ($0.dueAt, $0.id) < ($1.dueAt, $1.id) }) {
            if reminder.obsolete {
                decisions.append(
                    RecoveryDecision(
                        id: reminder.id, deliver: false,
                        reason: "the subject changed or was resolved while the host was unavailable"))
            } else if reminder.rule == .deadlineAhead || reminder.rule == .dateOnlyDeadline, reminder.deadlinePassed {
                decisions.append(
                    RecoveryDecision(
                        id: reminder.id, deliver: false,
                        reason: "the deadline passed while the host was unavailable; the overdue reminder replaces it"))
            } else if lowPriority.contains(reminder.rule) {
                if let previous = latestLowPriority[reminder.rule] {
                    decisions.append(
                        RecoveryDecision(
                            id: previous.id, deliver: false,
                            reason: "coalesced with a later missed reminder of the same kind"))
                }
                latestLowPriority[reminder.rule] = reminder
            } else {
                decisions.append(
                    RecoveryDecision(id: reminder.id, deliver: true, reason: "still relevant after the downtime"))
            }
        }
        for reminder in latestLowPriority.values.sorted(by: { $0.id < $1.id }) {
            decisions.append(
                RecoveryDecision(id: reminder.id, deliver: true, reason: "the latest missed reminder of its kind"))
        }
        return decisions
    }

    /// Whether a catch-up brief is allowed: at most one, and only within the configured window after its schedule.
    public static func allowsCatchUpBrief(scheduledAt: Date, now: Date, windowHours: Int, alreadyDelivered: Bool)
        -> Bool
    {
        !alreadyDelivered && now >= scheduledAt
            && now.timeIntervalSince(scheduledAt) <= TimeInterval(windowHours * 3600)
    }
}
