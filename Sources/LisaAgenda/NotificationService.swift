// Notification intents (NOTIFY-01, NOTIFY-03, plan §6.4): identities, coalescing, routing and per-device deliveries.

import Foundation
import LisaDelivery
import LisaDomain
import LisaLogging
import LisaPolicy
import LisaPorts
import LisaTime

/// Decides notification occurrences and records one delivery per device in the same transaction (REM-03).
public final class NotificationService: Sendable {
    private let clock: any WallClock
    private let logger: Logger
    private let outbox: DeliveryOutbox

    public init(clock: any WallClock, logger: Logger, outbox: DeliveryOutbox) {
        self.clock = clock
        self.logger = logger
        self.outbox = outbox
    }

    /// The occurrence key of a reminder firing at `instant`: the reminder ID plus its scheduled instant.
    public static func reminderOccurrenceKey(_ reminder: Reminder, firingAt instant: Date) -> String {
        "reminder:\(reminder.id.rawValue):\(instant.millisecondsSince1970)"
    }

    /// The occurrence key of a brief-availability notification: one per local date and timezone, by policy.
    public static func briefOccurrenceKey(date: LocalDate, zone: TimeZoneID) -> String {
        "brief:\(date.iso):\(zone.identifier)"
    }

    public static func category(for rule: ReminderRule) -> NotificationCategory {
        switch rule {
        case .deadlineAhead, .dateOnlyDeadline: .reminder
        case .overdue: .overdue
        case .planBlockStart: .planBlock
        case .proposalFollowUp: .eventProposal
        case .commitmentChange: .commitmentChange
        }
    }

    /// Records the notification occurrence for a reminder firing now and routes it to every device.
    @discardableResult
    public func reminderDue(
        _ reminder: Reminder, firingAt instant: Date, task: LisaTask?, blockEnd: Date?, settings: OwnerSettings,
        in tx: any RecordWriting
    ) throws -> NotificationIntent? {
        guard settings.notifications.enabled else { return nil }
        let now = clock.now()
        let key = Self.reminderOccurrenceKey(reminder, firingAt: instant)
        if let existing = try tx.first(NotificationIntent.self, RecordQuery.all.filter("occurrence_key", equals: key)) {
            return existing
        }
        let category = Self.category(for: reminder.rule)
        let zone = settings.zone.timeZone
        let intent = try tx.insert(
            NotificationIntent(
                occurrenceKey: key, category: category, subject: .reminder(reminder.id),
                changeSequence: reminder.subjectChangeSequence, collapseKey: key,
                interruptionLevel: UrgencyRule.interruptionLevel(
                    category: category, task: task, now: now, settings: settings.notifications),
                titleHint: reminder.title,
                validUntil: DeliveryTiming.validUntil(
                    category: category, dueAt: instant, deadline: task?.deadline, blockEnd: blockEnd, zone: zone,
                    settings: settings.notifications),
                now: now))
        try route(intent, settings: settings, now: now, in: tx)
        return intent
    }

    /// Records an important change to a confirmed commitment. Earlier change occurrences for the same subject that
    /// have not been submitted to any device are coalesced into this one; one that was submitted is never coalesced.
    @discardableResult
    public func importantChange(
        _ subject: NotificationSubject, changeSequence: Int, titleHint: String?, settings: OwnerSettings,
        in tx: any RecordWriting
    ) throws -> NotificationIntent? {
        guard settings.notifications.enabled, settings.reminders.notifyCommitmentChanges else { return nil }
        let now = clock.now()
        let key = NotificationIntent.changeKey(subject: subject, changeSequence: changeSequence)
        if let existing = try tx.first(NotificationIntent.self, RecordQuery.all.filter("occurrence_key", equals: key)) {
            return existing
        }
        let prior = try tx.find(
            NotificationIntent.self,
            RecordQuery.all.filter("subject_key", equals: subject.key).filter(
                "category", equals: NotificationCategory.commitmentChange.rawValue)
        ).filter { $0.state == .active }
        let plan = ChangeNotificationPolicy.plan(
            newChangeSequence: changeSequence,
            prior: try prior.map { intent in
                PriorChangeOccurrence(
                    id: intent.id, changeSequence: intent.changeSequence,
                    anyDeliverySubmitted: try Self.anySubmitted(intent.id, in: tx))
            })
        for id in plan.coalesce {
            guard var earlier = prior.first(where: { $0.id == id }) else { continue }
            earlier.state = .coalesced
            earlier.updatedAt = now
            try tx.update(earlier)
            try DeliveryOutbox.suppressPending(
                payloadKey: "notification:\(id.rawValue)", reason: "coalesced into a later change", at: now, in: tx)
        }
        guard plan.createNew else { return nil }
        let intent = try tx.insert(
            NotificationIntent(
                occurrenceKey: key, category: .commitmentChange, subject: subject, changeSequence: changeSequence,
                collapseKey: NotificationIntent.changeCollapseKey(subject: subject), interruptionLevel: .active,
                titleHint: titleHint,
                validUntil: DeliveryTiming.validUntil(
                    category: .commitmentChange, dueAt: now, deadline: nil, blockEnd: nil,
                    zone: settings.zone.timeZone, settings: settings.notifications),
                now: now))
        try route(intent, settings: settings, now: now, in: tx)
        return intent
    }

    /// Records the brief-availability notification for a date. At most one per local date and timezone: a
    /// regenerated brief does not notify again. The record also marks the day's brief as dispatched.
    @discardableResult
    public func briefAvailable(_ brief: Brief, settings: OwnerSettings, in tx: any RecordWriting) throws
        -> NotificationIntent?
    {
        let now = clock.now()
        let key = Self.briefOccurrenceKey(date: brief.localDate, zone: brief.zone)
        if try tx.first(NotificationIntent.self, RecordQuery.all.filter("occurrence_key", equals: key)) != nil {
            return nil
        }
        let intent = try tx.insert(
            NotificationIntent(
                occurrenceKey: key, category: .brief, subject: .brief(brief.id), changeSequence: 0, collapseKey: key,
                interruptionLevel: .active, titleHint: nil,
                validUntil: DeliveryTiming.validUntil(
                    category: .brief, dueAt: now, deadline: nil, blockEnd: nil, zone: brief.zone.timeZone,
                    settings: settings.notifications),
                now: now))
        if settings.notifications.enabled && settings.notifications.notifyBriefAvailability {
            try route(intent, settings: settings, now: now, in: tx)
        }
        return intent
    }

    /// Creates one delivery per paired device. Devices that cannot receive it get a suppressed record with the
    /// reason, so no device is silently skipped.
    func route(_ intent: NotificationIntent, settings: OwnerSettings, now: Date, in tx: any RecordWriting) throws {
        let devices = try tx.find(
            DeviceRegistration.self, RecordQuery.all.filter("state", equals: DeviceState.active.rawValue))
        for decision in NotificationRouting.route(
            category: intent.category, level: intent.interruptionLevel, devices: devices)
        {
            guard let device = devices.first(where: { $0.id == decision.deviceID }) else { continue }
            let channel: DeliveryChannel = device.transport == .apns ? .push : .localNotification
            var delivery = Delivery(
                channel: channel, recipient: .device(device.id), payload: .notification(intent.id),
                idempotencyKey: DeliveryOutbox.notificationKey(
                    occurrenceKey: intent.occurrenceKey, deviceID: device.id),
                mode: outbox.mode(for: channel, settings: settings.delivery), notBefore: now,
                validUntil: intent.validUntil, now: now)
            if !decision.deliver {
                delivery.state = .suppressed
                delivery.stateReason = decision.suppressionReason
            }
            try DeliveryOutbox.enqueue(delivery, in: tx)
        }
        logger.info(
            "notification recorded",
            [
                "notification": .public(intent.id.rawValue), "category": .public(intent.category.rawValue),
                "devices": .count(devices.count),
            ])
    }

    /// Resolves the active occurrences of the given subjects and suppresses their pending deliveries on every
    /// device (acknowledgement, completion, deletion).
    @discardableResult
    public static func resolve(subjectKeys: [String], reason: String, at now: Date, in tx: any RecordWriting) throws
        -> Int
    {
        var resolved = 0
        for key in Set(subjectKeys) {
            let intents = try tx.find(NotificationIntent.self, RecordQuery.all.filter("subject_key", equals: key))
            for intent in intents where intent.state == .active {
                var updated = intent
                updated.state = .resolved
                updated.updatedAt = now
                try tx.update(updated)
                try DeliveryOutbox.suppressPending(
                    payloadKey: "notification:\(intent.id.rawValue)", reason: reason, at: now, in: tx)
                resolved += 1
            }
        }
        return resolved
    }

    static func anySubmitted(_ id: NotificationID, in tx: any RecordReading) throws -> Bool {
        try tx.find(Delivery.self, RecordQuery.all.filter("payload_key", equals: "notification:\(id.rawValue)"))
            .contains { $0.wasEverSubmitted }
    }
}
