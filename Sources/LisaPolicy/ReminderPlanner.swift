// Computes the reminder occurrences a commitment should have (REM-01, REM-02) without historical bursts.

import Foundation
import LisaDomain
import LisaTime

/// A reminder the policy wants to exist. `occurrenceKey` is stable, so recomputation never duplicates it.
public struct ReminderSpec: Hashable, Sendable {
    public var subject: ReminderSubject
    public var rule: ReminderRule
    public var dueAt: Date
    public var occurrenceKey: String
    public var subjectChangeSequence: Int
    public var title: String
}

/// Reminder timing rules.
public enum ReminderPlanner {
    /// Deadline reminders for a confirmed, active task. Only reminders still in the future are created, so a newly
    /// discovered item never receives every reminder it would have had in the past. When every configured offset has
    /// already passed but the deadline has not, a single reminder is due now — unless an offset reminder already
    /// exists for this deadline (`existingOccurrenceKeys` holds the occurrence keys of the task's stored reminders),
    /// because then the commitment was not discovered late and that reminder is its last one (D-16).
    public static func deadlineReminders(
        for task: LisaTask, settings: ReminderSettings, zone: TimeZone, now: Date,
        existingOccurrenceKeys: Set<String> = []
    ) -> [ReminderSpec] {
        guard task.isConfirmedCommitment, task.status.isActive, let deadline = task.deadline else { return [] }
        let base = "task:\(task.id.rawValue):\(task.changeSequence)"
        switch deadline {
        case .at(let instant, _):
            guard instant > now else { return [] }
            var specs = settings.deadlineOffsetsMinutes.sorted(by: >).compactMap { offset -> ReminderSpec? in
                let due = instant.addingTimeInterval(-TimeInterval(offset * 60))
                guard due > now else { return nil }
                return ReminderSpec(
                    subject: .task(task.id), rule: .deadlineAhead, dueAt: due,
                    occurrenceKey: "deadline:\(base):\(offset)",
                    subjectChangeSequence: task.changeSequence, title: task.title)
            }
            let soonKey = "deadline:\(base):soon"
            let offsetScheduled = existingOccurrenceKeys.contains { $0.hasPrefix("deadline:\(base):") && $0 != soonKey }
            if specs.isEmpty, !offsetScheduled {
                specs.append(
                    ReminderSpec(
                        subject: .task(task.id), rule: .deadlineAhead, dueAt: now, occurrenceKey: soonKey,
                        subjectChangeSequence: task.changeSequence, title: task.title))
            }
            return specs
        case .onDate(let date):
            // Date-only deadlines are reminded only at an explicitly configured time; the deadline stays date-only.
            guard let time = settings.dateOnlyReminderTime else { return [] }
            let due = ZoneRules.instant(for: LocalDateTime(date: date, time: time), in: zone)
            guard due > now else { return [] }
            return [
                ReminderSpec(
                    subject: .task(task.id), rule: .dateOnlyDeadline, dueAt: due, occurrenceKey: "dateonly:\(base)",
                    subjectChangeSequence: task.changeSequence, title: task.title)
            ]
        }
    }

    /// At most one overdue reminder per local day for a confirmed task that is past its deadline.
    public static func overdueReminder(for task: LisaTask, settings: ReminderSettings, zone: TimeZone, now: Date)
        -> ReminderSpec?
    {
        guard task.isConfirmedCommitment, task.status.isActive, let deadline = task.deadline,
            deadline.latestInstant(in: zone) <= now
        else { return nil }
        let today = ZoneRules.localDate(for: now, in: zone)
        let scheduled = ZoneRules.instant(for: LocalDateTime(date: today, time: settings.overdueReminderTime), in: zone)
        return ReminderSpec(
            subject: .task(task.id), rule: .overdue, dueAt: max(scheduled, now),
            occurrenceKey: "overdue:task:\(task.id.rawValue):\(today.iso)", subjectChangeSequence: task.changeSequence,
            title: task.title)
    }

    /// A reminder shortly before an accepted or locked plan block starts.
    public static func planBlockReminder(planID: PlanID, block: PlanBlock, settings: ReminderSettings, now: Date)
        -> ReminderSpec?
    {
        guard block.kind != .fixedEvent, block.state == .accepted || block.state == .locked, block.range.start > now
        else {
            return nil
        }
        let due = block.range.start.addingTimeInterval(-TimeInterval(settings.planBlockLeadMinutes * 60))
        return ReminderSpec(
            subject: .planBlock(planID: planID, blockID: block.blockID), rule: .planBlockStart, dueAt: max(due, now),
            occurrenceKey: "block:\(planID.rawValue):\(block.blockID):\(block.range.start.millisecondsSince1970)",
            subjectChangeSequence: 0, title: block.title)
    }

    /// At most one follow-up per local day for an unresolved event proposal.
    public static func proposalFollowUp(
        for proposal: EventProposal, settings: ReminderSettings, zone: TimeZone, now: Date
    ) -> ReminderSpec? {
        guard proposal.matchState.isUnresolved else { return nil }
        let today = ZoneRules.localDate(for: now, in: zone)
        if let last = proposal.lastFollowUpAt, ZoneRules.localDate(for: last, in: zone) == today { return nil }
        let scheduled = ZoneRules.instant(
            for: LocalDateTime(date: today, time: settings.proposalFollowUpTime), in: zone)
        return ReminderSpec(
            subject: .proposal(proposal.id), rule: .proposalFollowUp, dueAt: max(scheduled, now),
            occurrenceKey: "proposal:\(proposal.id.rawValue):\(today.iso)",
            subjectChangeSequence: proposal.changeSequence,
            title: proposal.title)
    }

    /// Whether an existing reminder is obsolete because its subject changed or finished (REM-01).
    public static func isObsolete(_ reminder: Reminder, task: LisaTask?) -> Bool {
        guard case .task = reminder.subject else { return false }
        guard let task else { return true }
        if !task.status.isActive || !task.isConfirmedCommitment { return true }
        return reminder.subjectChangeSequence != task.changeSequence && reminder.rule != .overdue
    }
}
