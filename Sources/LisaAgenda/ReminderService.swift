// Reminders (REM-01, REM-04, CALL-01): recomputation, dispatch with escalation, owner actions and recovery.

import Foundation
import LisaDelivery
import LisaDomain
import LisaLogging
import LisaPolicy
import LisaPorts
import LisaTime

/// What a reminder synchronization changed.
public struct ReminderSyncReport: Hashable, Sendable {
    public var created = 0
    public var retitled = 0
    public var cancelled = 0
}

/// Reminder lifecycle. Only the host decides when reminders fire; devices only report actions.
public final class ReminderService: Sendable {
    /// Minutes between the notification and a call escalation, so an acknowledgement can still prevent the call.
    public static let callGraceMinutes = 5
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let settings: any SettingsSource
    private let notifications: NotificationService
    private let outbox: DeliveryOutbox

    public init(
        store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource,
        notifications: NotificationService, outbox: DeliveryOutbox
    ) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
        self.notifications = notifications
        self.outbox = outbox
    }

    /// Recomputes reminders from current tasks, accepted plan blocks and unresolved proposals, and cancels obsolete
    /// ones. Existing occurrences are matched by their stable key, so recomputation never duplicates a reminder.
    @discardableResult
    public func sync() throws -> ReminderSyncReport {
        let owner = try settings.currentSettings()
        let zone = owner.zone.timeZone
        let now = clock.now()
        let today = ZoneRules.localDate(for: now, in: zone)
        return try store.write { tx in
            var report = ReminderSyncReport()
            let active = try tx.find(
                LisaTask.self,
                RecordQuery.all.filter(
                    "status", in: [TaskStatus.open, .inProgress, .blocked].map { .text($0.rawValue) }))
            var specs: [ReminderSpec] = []
            for task in active {
                specs += ReminderPlanner.deadlineReminders(for: task, settings: owner.reminders, zone: zone, now: now)
                if let overdue = ReminderPlanner.overdueReminder(
                    for: task, settings: owner.reminders, zone: zone, now: now)
                {
                    specs.append(overdue)
                }
            }
            for date in [today, today.adding(days: 1)] {
                guard
                    let plan = try tx.first(
                        Plan.self, RecordQuery.all.filter("natural_key", equals: Plan.key(date: date, zone: owner.zone))
                    )
                else { continue }
                for block in plan.blocks {
                    if let spec = ReminderPlanner.planBlockReminder(
                        planID: plan.id, block: block, settings: owner.reminders, now: now)
                    {
                        specs.append(spec)
                    }
                }
            }
            for proposal in try tx.find(EventProposal.self, .all) where proposal.matchState.isUnresolved {
                if let spec = ReminderPlanner.proposalFollowUp(
                    for: proposal, settings: owner.reminders, zone: zone, now: now)
                {
                    specs.append(spec)
                }
            }
            for spec in specs {
                if var existing = try tx.first(
                    Reminder.self, RecordQuery.all.filter("occurrence_key", equals: spec.occurrenceKey))
                {
                    if existing.state == .scheduled, existing.title != spec.title {
                        existing.title = spec.title
                        existing.updatedAt = now
                        try tx.update(existing)
                        report.retitled += 1
                    }
                    continue
                }
                try tx.insert(
                    Reminder(
                        subject: spec.subject, rule: spec.rule, dueAt: spec.dueAt, occurrenceKey: spec.occurrenceKey,
                        subjectChangeSequence: spec.subjectChangeSequence, title: spec.title, now: now))
                report.created += 1
            }
            let pending = try tx.find(
                Reminder.self,
                RecordQuery.all.filter("state", in: [.text("scheduled"), .text("snoozed"), .text("delivered")]))
            for reminder in pending {
                guard let reason = try Self.obsolescence(of: reminder, in: tx) else { continue }
                try Self.cancel(reminder, reason: reason, at: now, in: tx)
                report.cancelled += 1
            }
            return report
        }
    }

    /// Why a reminder no longer applies, or `nil` when it still does.
    static func obsolescence(of reminder: Reminder, in tx: any RecordReading) throws -> String? {
        switch reminder.subject {
        case .task(let id):
            let task = try tx.get(LisaTask.self, id: id)
            return ReminderPlanner.isObsolete(reminder, task: task)
                ? (task.map { $0.status.isActive ? "the task changed" : "the task is \($0.status.rawValue)" }
                    ?? "the task was deleted")
                : nil
        case .planBlock(let planID, let blockID):
            guard let plan = try tx.get(Plan.self, id: planID),
                let block = plan.blocks.first(where: { $0.blockID == blockID })
            else { return "the plan block no longer exists" }
            guard block.state == .accepted || block.state == .locked else {
                return "the plan block is \(block.state.rawValue)"
            }
            return reminder.occurrenceKey.hasSuffix(":\(block.range.start.millisecondsSince1970)")
                ? nil : "the plan block moved"
        case .proposal(let id):
            guard let proposal = try tx.get(EventProposal.self, id: id) else { return "the proposal was deleted" }
            return proposal.matchState.isUnresolved ? nil : "the proposal was resolved"
        case .occurrenceChange(let id):
            return try tx.get(CalendarOccurrence.self, id: id) == nil ? "the event was removed" : nil
        }
    }

    /// Cancels a reminder and suppresses everything still pending for it on every channel and device.
    static func cancel(_ reminder: Reminder, reason: String, at now: Date, in tx: any RecordWriting) throws {
        var updated = reminder
        updated.state = .cancelled(reason: reason)
        updated.updatedAt = now
        try tx.update(updated)
        try NotificationService.resolve(
            subjectKeys: [NotificationSubject.reminder(reminder.id).key], reason: reason, at: now, in: tx)
        try DeliveryOutbox.suppressPending(
            payloadKey: "reminder:\(reminder.id.rawValue)", reason: reason, at: now, in: tx)
    }

    /// Fires due reminders: records the notification occurrence, optional email copies and, for urgent confirmed
    /// deadlines, a call escalation that the outbox gate re-checks at send time.
    @discardableResult
    public func dispatchDue(limit: Int = 50) throws -> Int {
        let owner = try settings.currentSettings()
        let now = clock.now()
        let due = try store.read { tx in
            try tx.find(
                Reminder.self,
                RecordQuery.all.filter("state", in: [.text("scheduled"), .text("snoozed")]).filter(
                    "due_at", .lessOrEqual, .instant(now)
                ).sorted(by: "due_at")
            ).filter { $0.isDue(at: now) }.prefix(limit)
        }
        var fired = 0
        for reminder in due {
            try store.write { tx in
                guard let current = try tx.get(Reminder.self, id: reminder.id), current.isDue(at: now) else { return }
                if let reason = try Self.obsolescence(of: current, in: tx) {
                    try Self.cancel(current, reason: reason, at: now, in: tx)
                    return
                }
                try fire(current, owner: owner, now: now, in: tx)
                fired += 1
            }
        }
        return fired
    }

    func fire(_ reminder: Reminder, owner: OwnerSettings, now: Date, in tx: any RecordWriting) throws {
        let firingAt: Date = if case .snoozed(let until) = reminder.state { until } else { reminder.dueAt }
        var task: LisaTask?
        var blockEnd: Date?
        switch reminder.subject {
        case .task(let id): task = try tx.get(LisaTask.self, id: id)
        case .planBlock(let planID, let blockID):
            blockEnd = try tx.get(Plan.self, id: planID)?.blocks.first { $0.blockID == blockID }?.range.end
        case .proposal(let id):
            if var proposal = try tx.get(EventProposal.self, id: id) {
                proposal.lastFollowUpAt = now
                proposal.updatedAt = now
                try tx.update(proposal)
            }
        case .occurrenceChange: break
        }
        var updated = reminder
        updated.state = .delivered(at: now)
        if let task {
            updated.urgentDeadline = UrgencyRule.isUrgentDeadline(
                task, now: now, windowMinutes: owner.notifications.urgentDeadlineWindowMinutes)
        }
        updated.updatedAt = now
        let saved = try tx.update(updated)
        try notifications.reminderDue(
            saved, firingAt: firingAt, task: task, blockEnd: blockEnd, settings: owner, in: tx)
        let occurrence = NotificationService.reminderOccurrenceKey(saved, firingAt: firingAt)
        let validUntil = task?.deadline?.latestInstant(in: owner.zone.timeZone)
        if owner.reminders.emailReminders, owner.delivery.emailEnabled {
            for address in owner.delivery.approvedEmailAddresses {
                try DeliveryOutbox.enqueue(
                    Delivery(
                        channel: .email, recipient: .emailAddress(address), payload: .reminder(saved.id),
                        idempotencyKey: "email:\(occurrence):\(address.lowercased())",
                        mode: outbox.mode(for: .email, settings: owner.delivery), notBefore: now,
                        validUntil: validUntil, now: now),
                    in: tx)
            }
        }
        if let task, owner.calls.enabled, let number = owner.calls.approvedNumber,
            UrgencyRule.isUrgentDeadline(task, now: now, windowMinutes: owner.calls.urgencyWindowMinutes)
        {
            try DeliveryOutbox.enqueue(
                Delivery(
                    channel: .call, recipient: .phoneNumber(number), payload: .reminder(saved.id),
                    idempotencyKey: DeliveryOutbox.callKey(taskID: task.id, reminderOccurrenceKey: occurrence),
                    mode: outbox.mode(for: .call, settings: owner.delivery),
                    notBefore: now.addingTimeInterval(TimeInterval(Self.callGraceMinutes * 60)), validUntil: validUntil,
                    now: now),
                in: tx)
        }
    }

    /// Applies an owner action. Acknowledgement stops this occurrence's repeats and escalation but not later
    /// reminders; it never completes the task (REM-01). Completion of the task itself goes through the task service.
    public func act(_ action: ReminderAction, on id: ReminderID, expectedRevision: Revision?, by principal: Principal)
        throws
        -> Reminder
    {
        switch principal {
        case .localOwner, .pairedDevice, .demonstration: break
        case .runtime, .model: throw DomainError.notPermitted("reminders are acknowledged only by the owner")
        }
        let owner = try settings.currentSettings()
        let now = clock.now()
        return try store.write { tx in
            var reminder = try tx.require(Reminder.self, id: id)
            if let expectedRevision, expectedRevision != reminder.revision {
                throw StoreError.conflict(
                    collection: Reminder.collectionName, id: id.rawValue, expected: expectedRevision,
                    actual: reminder.revision)
            }
            try reminder.apply(action, at: now, snoozeMinutes: owner.reminders.snoozeMinutes)
            let saved = try tx.update(reminder)
            let reason =
                switch action {
                case .acknowledge: "acknowledged"
                case .snooze: "snoozed"
                case .dismiss: "dismissed"
                case .complete: "completed"
                }
            try NotificationService.resolve(
                subjectKeys: [NotificationSubject.reminder(id).key], reason: reason, at: now, in: tx)
            try DeliveryOutbox.suppressPending(payloadKey: "reminder:\(id.rawValue)", reason: reason, at: now, in: tx)
            try tx.insert(
                AuditEvent(
                    action: "reminder.\(action.rawValue)", actor: principal, at: now, affected: [id.rawValue],
                    outcome: .succeeded, detail: "state=\(saved.state.name)"))
            return saved
        }
    }

    /// Cancels every reminder of a subject (task completed, cancelled or deleted) and suppresses its deliveries.
    @discardableResult
    public func cancelAll(subjectKey: String, reason: String) throws -> Int {
        let now = clock.now()
        return try store.write { tx in
            let reminders = try tx.find(Reminder.self, RecordQuery.all.filter("subject_key", equals: subjectKey))
            var cancelled = 0
            for reminder in reminders where !reminder.state.isTerminal {
                try Self.cancel(reminder, reason: reason, at: now, in: tx)
                cancelled += 1
            }
            return cancelled
        }
    }

    /// Reconciles reminders missed while the host was down (REM-04): obsolete ones are suppressed, past deadline
    /// reminders give way to the overdue reminder, and low-priority kinds are coalesced to the latest. Every skipped
    /// reminder is recorded with its reason.
    @discardableResult
    public func recover() throws -> [RecoveryDecision] {
        let now = clock.now()
        let zone = try settings.currentSettings().zone.timeZone
        return try store.write { tx in
            let missed = try tx.find(
                Reminder.self,
                RecordQuery.all.filter("state", in: [.text("scheduled"), .text("snoozed")]).filter(
                    "due_at", .lessOrEqual, .instant(now))
            ).filter { $0.isDue(at: now) }
            var inputs: [MissedReminder] = []
            for reminder in missed {
                var deadlinePassed = false
                if case .task(let id) = reminder.subject, let deadline = try tx.get(LisaTask.self, id: id)?.deadline {
                    deadlinePassed = deadline.latestInstant(in: zone) <= now
                }
                inputs.append(
                    MissedReminder(
                        id: reminder.id, rule: reminder.rule, dueAt: reminder.dueAt,
                        obsolete: try Self.obsolescence(of: reminder, in: tx) != nil, deadlinePassed: deadlinePassed))
            }
            let decisions = RecoveryPolicy.decide(inputs)
            for decision in decisions where !decision.deliver {
                guard var reminder = missed.first(where: { $0.id == decision.id }) else { continue }
                reminder.state = .suppressed(reason: decision.reason)
                reminder.updatedAt = now
                try tx.update(reminder)
                try tx.insert(
                    AuditEvent(
                        action: "reminder.recovery-skipped", actor: .runtime, at: now, affected: [reminder.id.rawValue],
                        outcome: .skipped, detail: decision.reason))
            }
            return decisions
        }
    }
}
