// Send-time content for reminders, briefs and notifications, with staleness and supersession re-checks (§6.4).

import Foundation
import LisaDelivery
import LisaDomain
import LisaPolicy
import LisaPorts
import LisaTime

/// Prepares what each delivery carries at the moment it is sent. Anything resolved, superseded or changed since the
/// decision is reported as not eligible, so the outbox suppresses it instead of sending stale content.
public struct AgendaContent: DeliveryContentProvider {
    private let store: any RecordStore

    public init(store: any RecordStore) {
        self.store = store
    }

    public func prepare(_ delivery: Delivery, settings: OwnerSettings, now: Date) throws -> PreparedDelivery {
        try store.read { tx in
            switch delivery.payload {
            case .notification(let id): try notification(id, settings: settings, now: now, in: tx)
            case .reminder(let id): try reminder(id, channel: delivery.channel, settings: settings, now: now, in: tx)
            case .brief(let id): try brief(id, in: tx)
            }
        }
    }

    func notification(_ id: NotificationID, settings: OwnerSettings, now: Date, in tx: any RecordReading) throws
        -> PreparedDelivery
    {
        guard let intent = try tx.get(NotificationIntent.self, id: id) else {
            return .notEligible(reason: "the notification no longer exists")
        }
        guard intent.state == .active else {
            return .notEligible(reason: "the notification was \(intent.state.rawValue)")
        }
        guard now < intent.validUntil else { return .notEligible(reason: "expired") }
        let subjectKind: String
        let subjectID: String
        let revision: Revision
        switch intent.subject {
        case .reminder(let reminderID):
            guard let reminder = try tx.get(Reminder.self, id: reminderID) else {
                return .notEligible(reason: "the reminder was removed")
            }
            if case .delivered = reminder.state {
            } else {
                return .notEligible(reason: "the reminder is \(reminder.state.name)")
            }
            if case .task(let taskID) = reminder.subject {
                guard let task = try tx.get(LisaTask.self, id: taskID), task.status.isActive, task.isConfirmedCommitment
                else { return .notEligible(reason: "the task is no longer an open confirmed commitment") }
                subjectKind = "task"
                subjectID = taskID.rawValue
                revision = task.revision
            } else {
                subjectKind = "reminder"
                subjectID = reminderID.rawValue
                revision = reminder.revision
            }
        case .task(let taskID):
            guard let task = try tx.get(LisaTask.self, id: taskID) else {
                return .notEligible(reason: "the task was deleted")
            }
            if try superseded(intent, latest: task.changeSequence, in: tx) {
                return .notEligible(reason: "superseded by a later change")
            }
            (subjectKind, subjectID, revision) = ("task", taskID.rawValue, task.revision)
        case .occurrence(let occurrenceID):
            guard let occurrence = try tx.get(CalendarOccurrence.self, id: occurrenceID) else {
                return .notEligible(reason: "the event was removed")
            }
            if try superseded(intent, latest: occurrence.changeSequence, in: tx) {
                return .notEligible(reason: "superseded by a later change")
            }
            (subjectKind, subjectID, revision) = ("occurrence", occurrenceID.rawValue, occurrence.revision)
        case .proposal(let proposalID):
            guard let proposal = try tx.get(EventProposal.self, id: proposalID), proposal.matchState.isUnresolved else {
                return .notEligible(reason: "the proposal was resolved")
            }
            (subjectKind, subjectID, revision) = ("proposal", proposalID.rawValue, proposal.revision)
        case .brief(let briefID):
            guard let brief = try tx.get(Brief.self, id: briefID) else {
                return .notEligible(reason: "the brief was removed")
            }
            (subjectKind, subjectID, revision) = ("brief", briefID.rawValue, brief.revision)
        }
        return .notification(
            NotificationDraft(
                category: intent.category, level: intent.interruptionLevel,
                content: NotificationContentPolicy.content(for: intent, showTitle: true),
                notificationID: intent.id.rawValue, subjectKind: subjectKind, subjectID: subjectID,
                subjectRevision: revision.value, collapseKey: intent.collapseKey))
    }

    func superseded(_ intent: NotificationIntent, latest: Int, in tx: any RecordReading) throws -> Bool {
        ChangeNotificationPolicy.isSuperseded(
            occurrenceSequence: intent.changeSequence, latestSequence: latest,
            anySubmitted: try NotificationService.anySubmitted(intent.id, in: tx))
    }

    func reminder(
        _ id: ReminderID, channel: DeliveryChannel, settings: OwnerSettings, now: Date, in tx: any RecordReading
    ) throws -> PreparedDelivery {
        guard let reminder = try tx.get(Reminder.self, id: id) else {
            return .notEligible(reason: "the reminder was removed")
        }
        guard case .delivered = reminder.state else {
            return .notEligible(reason: "the reminder is \(reminder.state.name)")
        }
        let zone = settings.zone.timeZone
        var task: LisaTask?
        if case .task(let taskID) = reminder.subject {
            guard let current = try tx.get(LisaTask.self, id: taskID), current.status.isActive,
                current.isConfirmedCommitment
            else { return .notEligible(reason: "the task is no longer an open confirmed commitment") }
            task = current
        }
        let due = task?.deadline.map { AgendaText.deadline($0, zone: zone) }
        switch channel {
        case .email:
            let title = AgendaText.singleLine(reminder.title)
            var body = "Reminder: \(title)\n"
            if let due { body += "Due: \(due)\n" }
            body +=
                "\nYou can acknowledge or snooze this reminder in the Lisa app.\n-- \nSent by Lisa to an approved address."
            return .email(subject: "Reminder: \(String(title.prefix(120)))", textBody: body)
        case .call:
            guard let task else { return .notEligible(reason: "calls are only placed for commitments") }
            // The earlier reminders: this occurrence, delivered before the call's grace period and still not
            // acknowledged (an acknowledgement would have suppressed this call), and the commitment's earlier ones.
            let earlier = try tx.find(
                Reminder.self, RecordQuery.all.filter("subject_key", equals: reminder.subject.key)
            )
            .filter { other in
                guard case .delivered(let at) = other.state else { return false }
                return other.id == reminder.id ? at <= now.addingTimeInterval(-60) : other.dueAt < reminder.dueAt
            }
            // One counts only if it reached the owner (D-17, plan §6.8).
            let outstanding = try earlier.contains { try Self.reachedOwner($0, in: tx) }
            let spoken =
                "This is Lisa with an urgent reminder. \(AgendaText.singleLine(task.title)) is due"
                + (due.map { " at \($0)." } ?? ".")
            return .call(
                spokenText: spoken,
                gate: CallContext(
                    task: task, now: now, zone: zone, settings: settings.calls,
                    quietHours: settings.reminders.quietHours,
                    destination: nil, earlierReminderUnacknowledged: outstanding,
                    callsForCommitmentToday: 0, callsToday: 0, basedOnProvisionalPlan: false))
        case .push, .localNotification:
            return .notEligible(reason: "reminder notifications are delivered through notification occurrences")
        }
    }

    /// Whether one of a reminder's notification or email deliveries was accepted by a provider or presented locally.
    /// Failed, unknown, pending and dry-run deliveries reached no one, so they never count toward a call.
    static func reachedOwner(_ reminder: Reminder, in tx: any RecordReading) throws -> Bool {
        let notifications = try tx.find(
            NotificationIntent.self,
            RecordQuery.all.filter("subject_key", equals: NotificationSubject.reminder(reminder.id).key))
        let payloadKeys = ["reminder:\(reminder.id.rawValue)"] + notifications.map { "notification:\($0.id.rawValue)" }
        for payloadKey in payloadKeys {
            let reached = try tx.find(Delivery.self, RecordQuery.all.filter("payload_key", equals: payloadKey))
                .contains { $0.channel != .call && [.acceptedByProvider, .confirmedDelivered].contains($0.state) }
            if reached { return true }
        }
        return false
    }

    func brief(_ id: BriefID, in tx: any RecordReading) throws -> PreparedDelivery {
        guard let brief = try tx.get(Brief.self, id: id) else { return .notEligible(reason: "the brief was removed") }
        return .email(
            subject: "Your Lisa brief for \(brief.localDate.iso)",
            textBody: brief.text + "\n-- \nSent by Lisa to an approved address.")
    }
}

/// Small text helpers for delivery content.
enum AgendaText {
    static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func deadline(_ deadline: Deadline, zone: TimeZone) -> String {
        switch deadline {
        case .at(let instant, _):
            let local = ZoneRules.local(for: instant, in: zone)
            return "\(local.date.iso) \(String(format: "%02d:%02d", local.time.hour, local.time.minute))"
        case .onDate(let date):
            return date.iso
        }
    }
}
