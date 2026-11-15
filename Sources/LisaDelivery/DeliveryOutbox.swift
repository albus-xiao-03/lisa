// The persistent delivery outbox (REM-03, NOTIFY-03): transactional enqueue, suppression and receipts; leased claims.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// Lisa's sending identity for email.
public struct EmailSender: Hashable, Sendable {
    public var address: String
    public var name: String?

    public init(address: String, name: String?) {
        self.address = address
        self.name = name
    }

    /// The domain used in generated message IDs.
    public var domain: String {
        address.split(separator: "@").last.map(String.init).flatMap { $0.isEmpty ? nil : $0 } ?? "lisa.invalid"
    }
}

/// The configured live transports. A live delivery on a channel without one fails with a configuration reason; it is
/// never silently captured or sent another way.
public struct LiveTransports: Sendable {
    public var email: (any EmailTransport)?
    public var call: (any CallTransport)?
    public var push: (any PushTransport)?
    public var localNotification: (any LocalNotificationTransport)?

    public init(
        email: (any EmailTransport)? = nil, call: (any CallTransport)? = nil, push: (any PushTransport)? = nil,
        localNotification: (any LocalNotificationTransport)? = nil
    ) {
        self.email = email
        self.call = call
        self.push = push
        self.localNotification = localNotification
    }
}

/// Counts from one outbox run.
public struct DeliveryRunSummary: Hashable, Sendable {
    public var claimed = 0
    public var recoveredForRetry = 0
    public var markedOutcomeUnknown = 0
    public var deferred = 0
    public var retried = 0
    public var finished: [DeliveryState: Int] = [:]

    public init() {}
}

/// The outbox. Static members run inside the caller's transaction, so delivery records are created, suppressed or
/// cancelled atomically with the decision that caused them.
public final class DeliveryOutbox: Sendable {
    let store: any RecordStore
    let clock: any WallClock
    let logger: Logger
    let settings: any SettingsSource
    let content: any DeliveryContentProvider
    let live: LiveTransports
    let dryRunEmail: DryRunEmailTransport
    let dryRunCall: DryRunCallTransport
    let dryRunPush: DryRunPushTransport
    let dryRunLocal: DryRunLocalNotificationTransport
    let tokenFeedback: (any DeviceTokenFeedback)?
    let sender: EmailSender
    let random: @Sendable () -> Double

    public init(
        store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource,
        content: any DeliveryContentProvider, live: LiveTransports, recorder: any DryRunRecorder,
        tokenFeedback: (any DeviceTokenFeedback)?, sender: EmailSender,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
        self.content = content
        self.live = live
        self.dryRunEmail = DryRunEmailTransport(recorder: recorder, clock: clock)
        self.dryRunCall = DryRunCallTransport(recorder: recorder, clock: clock)
        self.dryRunPush = DryRunPushTransport(recorder: recorder, clock: clock)
        self.dryRunLocal = DryRunLocalNotificationTransport(recorder: recorder, clock: clock)
        self.tokenFeedback = tokenFeedback
        self.sender = sender
        self.random = random
    }

    /// The mode a new delivery on `channel` gets. Email, calls and pushes follow the configured modes; local
    /// notifications are live only inside the Mac app, which supplies the local transport.
    public func mode(for channel: DeliveryChannel, settings: DeliverySettings) -> DeliveryMode {
        switch channel {
        case .email: settings.emailMode
        case .call: settings.callMode
        case .push: settings.pushMode
        case .localNotification: live.localNotification == nil ? .dryRun : .live
        }
    }

    // MARK: - Transactional operations

    /// The idempotency key of one notification occurrence on one device; unique per (occurrence, device).
    public static func notificationKey(occurrenceKey: String, deviceID: DeviceID) -> String {
        "notify:\(occurrenceKey):device:\(deviceID.rawValue)"
    }

    /// Stores `delivery` unless one with the same idempotency key exists, in which case the existing one is returned.
    @discardableResult
    public static func enqueue(_ delivery: Delivery, in tx: any RecordWriting) throws -> Delivery {
        let existing = try tx.first(
            Delivery.self, RecordQuery.all.filter("idempotency_key", equals: delivery.idempotencyKey))
        if let existing { return existing }
        return try tx.insert(delivery)
    }

    /// Suppresses every pending delivery of a payload on every channel and device.
    @discardableResult
    public static func suppressPending(payloadKey: String, reason: String, at now: Date, in tx: any RecordWriting)
        throws -> [Delivery]
    {
        let pending = try tx.find(
            Delivery.self,
            RecordQuery.all.filter("payload_key", equals: payloadKey).filter(
                "state", equals: DeliveryState.pending.rawValue))
        return try pending.map { delivery in
            var delivery = delivery
            delivery.state = .suppressed
            delivery.stateReason = reason
            delivery.updatedAt = now
            return try tx.update(delivery)
        }
    }

    /// Cancels pending deliveries to a recipient, for example a revoked device.
    @discardableResult
    public static func cancelPending(
        recipient: DeliveryRecipient, reason: String, at now: Date, in tx: any RecordWriting
    )
        throws -> Int
    {
        let pending = try tx.find(
            Delivery.self,
            RecordQuery.all.filter("recipient_key", equals: recipient.description).filter(
                "state", equals: DeliveryState.pending.rawValue))
        for delivery in pending {
            var delivery = delivery
            delivery.state = .cancelled
            delivery.stateReason = reason
            delivery.updatedAt = now
            try tx.update(delivery)
        }
        return pending.count
    }

    /// Records that a device reported a notification as presented (opened, or still in Notification Center). This
    /// is the only way a delivery becomes "confirmed delivered".
    @discardableResult
    public static func recordReceipt(
        notificationID: NotificationID, deviceID: DeviceID, at now: Date, in tx: any RecordWriting
    ) throws -> Delivery? {
        let deliveries = try tx.find(
            Delivery.self,
            RecordQuery.all.filter("payload_key", equals: "notification:\(notificationID.rawValue)").filter(
                "recipient_key", equals: DeliveryRecipient.device(deviceID).description))
        guard var delivery = deliveries.first else { return nil }
        guard [.acceptedByProvider, .outcomeUnknown, .inProgress].contains(delivery.state) else { return delivery }
        delivery.state = .confirmedDelivered
        delivery.stateReason = "reported by the device"
        delivery.leaseExpiresAt = nil
        delivery.updatedAt = now
        return try tx.update(delivery)
    }

    // MARK: - Worker

    /// Recovers deliveries whose lease expired: one still preparing is retried; one that was submitting becomes
    /// outcome unknown and is never resent automatically.
    @discardableResult
    public func recoverExpiredLeases() throws -> (retried: Int, outcomeUnknown: Int) {
        let now = clock.now()
        return try store.write { tx in
            let expired = try tx.find(
                Delivery.self,
                RecordQuery.all.filter("state", equals: DeliveryState.inProgress.rawValue).filter(
                    "lease_expires_at", .lessOrEqual, .instant(now)))
            var retried = 0
            var unknown = 0
            for delivery in expired {
                var delivery = delivery
                let submitting = delivery.attempts.last?.phase == .submitting
                if var attempt = delivery.attempts.popLast() {
                    attempt.finishedAt = now
                    attempt.result = submitting ? "lease expired during submission" : "lease expired before submission"
                    delivery.attempts.append(attempt)
                }
                delivery.leaseExpiresAt = nil
                delivery.updatedAt = now
                if submitting {
                    delivery.state = .outcomeUnknown
                    delivery.stateReason = "the host stopped while the request was being submitted; it is not resent"
                    unknown += 1
                    try tx.insert(Self.audit(delivery, outcome: .failed, at: now))
                } else {
                    delivery.state = .pending
                    delivery.nextAttemptAt = now
                    retried += 1
                }
                try tx.update(delivery)
            }
            return (retried, unknown)
        }
    }

    /// Claims due pending deliveries under a lease and opens a *preparing* attempt for each.
    public func claimDue(limit: Int = 20) throws -> [Delivery] {
        let now = clock.now()
        let leaseSeconds = max(30, try settings.currentSettings().delivery.leaseSeconds)
        return try store.write { tx in
            let due = try tx.find(
                Delivery.self,
                RecordQuery.all.filter("state", equals: DeliveryState.pending.rawValue)
                    .filter("next_attempt_at", .lessOrEqual, .instant(now)).sorted(by: "next_attempt_at")
                    .limited(to: limit))
            return try due.map { delivery in
                var delivery = delivery
                delivery.state = .inProgress
                delivery.leaseExpiresAt = now.addingTimeInterval(TimeInterval(leaseSeconds))
                delivery.attempts.append(
                    DeliveryAttempt(number: delivery.attempts.count + 1, startedAt: now, phase: .preparing))
                delivery.updatedAt = now
                return try tx.update(delivery)
            }
        }
    }

    /// Recovers expired leases, then claims and processes due deliveries one at a time.
    public func runOnce(limit: Int = 20) async throws -> DeliveryRunSummary {
        var summary = DeliveryRunSummary()
        let recovered = try recoverExpiredLeases()
        summary.recoveredForRetry = recovered.retried
        summary.markedOutcomeUnknown = recovered.outcomeUnknown
        let claimed = try claimDue(limit: limit)
        summary.claimed = claimed.count
        for delivery in claimed {
            switch try await process(delivery) {
            case .finished(let state): summary.finished[state, default: 0] += 1
            case .deferred: summary.deferred += 1
            case .retrying: summary.retried += 1
            case .leaseLost: break
            }
        }
        return summary
    }

    static func audit(_ delivery: Delivery, outcome: AuditOutcome, at now: Date) -> AuditEvent {
        AuditEvent(
            action: "delivery.\(delivery.channel.rawValue)", actor: .runtime, at: now,
            affected: [delivery.id.rawValue, delivery.payloadKey], outcome: outcome,
            detail:
                "state=\(delivery.state.rawValue) mode=\(delivery.mode.rawValue) reason=\(delivery.stateReason ?? "-")")
    }
}
