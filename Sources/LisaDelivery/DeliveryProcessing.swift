// Processing one claimed delivery: re-checks, recipient enforcement, the call gate, quiet hours, the submitting phase
// and the classification of transport results (plan §6.4).

import Foundation
import LisaDomain
import LisaPolicy
import LisaPorts
import LisaTime

/// What happened to one claimed delivery.
public enum ProcessOutcome: Hashable, Sendable {
    case finished(DeliveryState)
    case deferred(until: Date)
    case retrying(at: Date)
    /// The lease was taken over (for example by lease recovery); nothing was done.
    case leaseLost
}

enum OutgoingRequest {
    case email(EmailEnvelope)
    case call(CallRequest)
    case push(PushMessage)
    case local(NotificationPresentation, deliveryID: String)
}

enum Resolution {
    case ready(OutgoingRequest)
    case refused(DeliveryState, reason: String, audit: AuditOutcome)
}

extension DeliveryOutbox {
    /// Processes a delivery claimed by `claimDue`. Nothing is transmitted before the attempt is durably marked as
    /// submitting, so a crash before that point leads to a retry and a crash after it to "outcome unknown".
    public func process(_ claimed: Delivery) async throws -> ProcessOutcome {
        let owner = try settings.currentSettings()
        let now = clock.now()
        let zone = owner.zone.timeZone
        if let validUntil = claimed.validUntil, now >= validUntil {
            return try finish(claimed, state: .cancelled, reason: "expired", audit: .skipped)
        }
        let prepared: PreparedDelivery
        do {
            prepared = try content.prepare(claimed, settings: owner, now: now)
        } catch {
            return try retryOrFail(claimed, reason: "the content could not be prepared", retryAfter: nil, owner: owner)
        }
        let request: OutgoingRequest
        switch try resolve(claimed, prepared, owner: owner, now: now, zone: zone) {
        case .refused(let state, let reason, let audit):
            return try finish(claimed, state: state, reason: reason, audit: audit)
        case .ready(let outgoing):
            request = outgoing
        }
        // Email is not an interruption; notifications are deferred out of quiet hours. Calls were already refused
        // inside quiet hours by the call gate.
        if claimed.channel == .push || claimed.channel == .localNotification {
            switch DeliveryTiming.quietHours(
                at: now, quiet: owner.reminders.quietHours, zone: zone, validUntil: claimed.validUntil)
            {
            case .sendNow: break
            case .deferUntil(let date): return try deferDelivery(claimed, until: date)
            case .expire:
                return try finish(claimed, state: .cancelled, reason: "expired during quiet hours", audit: .skipped)
            }
        }
        guard let submitting = try markSubmitting(claimed) else { return .leaseLost }
        let result = await send(request, mode: claimed.mode)
        return try record(result, for: submitting, owner: owner)
    }

    func resolve(_ delivery: Delivery, _ prepared: PreparedDelivery, owner: OwnerSettings, now: Date, zone: TimeZone)
        throws -> Resolution
    {
        switch (prepared, delivery.recipient) {
        case (.notEligible(let reason), _):
            return .refused(.suppressed, reason: reason, audit: .skipped)
        case (.email(let subject, let body), .emailAddress(let address)) where delivery.channel == .email:
            guard owner.delivery.emailEnabled else {
                return .refused(.suppressed, reason: "email delivery is turned off", audit: .skipped)
            }
            guard owner.delivery.isApproved(emailAddress: address) else {
                return .refused(.suppressed, reason: "the recipient is not an owner-approved address", audit: .denied)
            }
            return .ready(
                .email(
                    EmailEnvelope(
                        from: sender.address, fromName: sender.name, to: [address], subject: subject, textBody: body,
                        messageID: "<\(delivery.id.rawValue)@\(sender.domain)>")))
        case (.call(let spokenText, var gate), .phoneNumber(let number)) where delivery.channel == .call:
            gate.destination = number
            let counts = try callCounts(taskID: gate.task.id, now: now, zone: zone, excluding: delivery.id)
            gate.callsToday = counts.today
            gate.callsForCommitmentToday = counts.forTask
            let decision = CallEligibility.evaluate(gate)
            guard decision.allowed else {
                let reason = "the call is not permitted: " + decision.unmetConditions.joined(separator: "; ")
                return .refused(.suppressed, reason: reason, audit: .denied)
            }
            return .ready(.call(CallRequest(to: number, spokenText: spokenText)))
        case (.notification(let draft), .device(let deviceID)):
            return try resolveNotification(delivery, draft, deviceID: deviceID, now: now)
        default:
            return .refused(
                .failed, reason: "the payload does not match the delivery channel or recipient", audit: .failed)
        }
    }

    private func resolveNotification(_ delivery: Delivery, _ draft: NotificationDraft, deviceID: DeviceID, now: Date)
        throws -> Resolution
    {
        guard let device = try store.read({ try $0.get(DeviceRegistration.self, id: deviceID) }),
            let decision = NotificationRouting.route(category: draft.category, level: draft.level, devices: [device])
                .first
        else { return .refused(.cancelled, reason: "the device is no longer paired", audit: .skipped) }
        guard decision.deliver else {
            return .refused(
                .suppressed, reason: decision.suppressionReason ?? "the device is not eligible", audit: .skipped)
        }
        let presentation = NotificationPresentation(
            titleKey: draft.content.titleKey, bodyKey: draft.content.bodyKey,
            itemTitle: decision.showTitle ? draft.content.itemTitle : nil,
            categoryIdentifier: draft.content.categoryIdentifier, threadIdentifier: draft.content.threadIdentifier,
            level: decision.level, notificationID: draft.notificationID, subjectKind: draft.subjectKind,
            subjectID: draft.subjectID, subjectRevision: draft.subjectRevision)
        switch (delivery.channel, device.transport) {
        case (.push, .apns):
            guard let token = device.pushToken, token.state == .active else {
                return .refused(.suppressed, reason: "the device has no active push registration", audit: .skipped)
            }
            let expiry = delivery.validUntil ?? now.addingTimeInterval(3600)
            return .ready(
                .push(
                    PushMessage(
                        deviceToken: token.token, environment: token.environment, topic: token.topic,
                        presentation: presentation, collapseID: draft.collapseKey, deliveryID: delivery.id.rawValue,
                        expiresAt: expiry)))
        case (.localNotification, .local):
            return .ready(.local(presentation, deliveryID: delivery.id.rawValue))
        default:
            return .refused(
                .failed, reason: "the delivery channel does not match the device's transport", audit: .failed)
        }
    }

    /// Calls already submitted today, overall and for one commitment. Dry-run captures count, so dry runs show the
    /// limits exactly as live operation would apply them.
    func callCounts(taskID: TaskID, now: Date, zone: TimeZone, excluding: DeliveryID) throws -> (
        today: Int, forTask: Int
    ) {
        let dayStart = ZoneRules.startOfDay(ZoneRules.localDate(for: now, in: zone), in: zone)
        let counted: Set<DeliveryState> = [
            .inProgress, .acceptedByProvider, .confirmedDelivered, .outcomeUnknown, .capturedDryRun,
        ]
        let calls = try store.read { tx in
            try tx.find(
                Delivery.self,
                RecordQuery.all.filter("channel", equals: DeliveryChannel.call.rawValue).filter(
                    "next_attempt_at", .greaterOrEqual, .instant(dayStart.addingTimeInterval(-86_400))))
        }
        let today = calls.filter { call in
            call.id != excluding && counted.contains(call.state)
                && call.attempts.contains { $0.phase == .submitting && $0.startedAt >= dayStart }
        }
        let prefix = "call:task:\(taskID.rawValue):"
        return (today.count, today.filter { $0.idempotencyKey.hasPrefix(prefix) }.count)
    }

    /// The idempotency key of a call escalation for one reminder occurrence of a commitment.
    public static func callKey(taskID: TaskID, reminderOccurrenceKey: String) -> String {
        "call:task:\(taskID.rawValue):\(reminderOccurrenceKey)"
    }

    func send(_ request: OutgoingRequest, mode: DeliveryMode) async -> TransportResult {
        switch (request, mode) {
        case (.email(let envelope), .dryRun): return await dryRunEmail.send(envelope)
        case (.call(let call), .dryRun): return await dryRunCall.place(call)
        case (.push(let message), .dryRun): return await dryRunPush.push(message)
        case (.local(let presentation, let deliveryID), .dryRun):
            return await dryRunLocal.present(presentation, deliveryID: deliveryID)
        case (.email(let envelope), .live):
            guard let transport = live.email, transport.mode == .live else { return Self.notConfigured("email") }
            return await transport.send(envelope)
        case (.call(let call), .live):
            guard let transport = live.call, transport.mode == .live else { return Self.notConfigured("call") }
            return await transport.place(call)
        case (.push(let message), .live):
            guard let transport = live.push, transport.mode == .live else { return Self.notConfigured("push") }
            return await transport.push(message)
        case (.local(let presentation, let deliveryID), .live):
            guard let transport = live.localNotification else { return Self.notConfigured("local notification") }
            return await transport.present(presentation, deliveryID: deliveryID)
        }
    }

    static func notConfigured(_ channel: String) -> TransportResult {
        .rejected(
            reason: "live \(channel) delivery is configured but no live transport is available",
            invalidatesRecipient: false,
            providerTimestamp: nil)
    }

    // MARK: - Persisting transitions

    /// Re-reads the delivery and applies `change` only if this worker still holds its lease.
    private func updateClaimed(_ claimed: Delivery, _ change: (inout Delivery) -> AuditOutcome?) throws -> Delivery? {
        let now = clock.now()
        return try store.write { tx in
            guard var current = try tx.get(Delivery.self, id: claimed.id), current.state == .inProgress,
                current.attempts.count == claimed.attempts.count
            else { return nil }
            let audit = change(&current)
            current.updatedAt = now
            let saved = try tx.update(current)
            if let audit { try tx.insert(Self.audit(saved, outcome: audit, at: now)) }
            return saved
        }
    }

    func markSubmitting(_ claimed: Delivery) throws -> Delivery? {
        let leaseSeconds = max(30, try settings.currentSettings().delivery.leaseSeconds)
        let now = clock.now()
        return try updateClaimed(claimed) { delivery in
            if var attempt = delivery.attempts.popLast() {
                attempt.phase = .submitting
                delivery.attempts.append(attempt)
            }
            delivery.leaseExpiresAt = now.addingTimeInterval(TimeInterval(leaseSeconds))
            return nil
        }
    }

    func finish(
        _ claimed: Delivery, state: DeliveryState, reason: String?, audit: AuditOutcome,
        providerReference: String? = nil
    )
        throws -> ProcessOutcome
    {
        let now = clock.now()
        let saved = try updateClaimed(claimed) { delivery in
            if var attempt = delivery.attempts.popLast() {
                attempt.finishedAt = now
                attempt.result = reason ?? state.rawValue
                attempt.providerReference = providerReference
                delivery.attempts.append(attempt)
            }
            delivery.state = state
            delivery.stateReason = reason
            delivery.leaseExpiresAt = nil
            return audit
        }
        guard let saved else { return .leaseLost }
        logger.info(
            "delivery finished",
            [
                "delivery": .public(saved.id.rawValue), "channel": .public(saved.channel.rawValue),
                "state": .public(state.rawValue),
            ])
        return .finished(state)
    }

    /// Puts a delivery back to pending without counting an attempt (nothing was transmitted).
    func deferDelivery(_ claimed: Delivery, until date: Date) throws -> ProcessOutcome {
        let saved = try updateClaimed(claimed) { delivery in
            _ = delivery.attempts.popLast()
            delivery.state = .pending
            delivery.stateReason = "deferred until quiet hours end"
            delivery.nextAttemptAt = date
            delivery.leaseExpiresAt = nil
            return nil
        }
        return saved == nil ? .leaseLost : .deferred(until: date)
    }

    /// Schedules a retry with exponential backoff and jitter inside the attempt limit and validity window, or fails.
    func retryOrFail(_ claimed: Delivery, reason: String, retryAfter: Date?, owner: OwnerSettings) throws
        -> ProcessOutcome
    {
        let now = clock.now()
        let limits = owner.delivery
        let attempt = claimed.attempts.count
        guard attempt < max(1, limits.maxAttempts) else {
            return try finish(
                claimed, state: .failed, reason: "\(reason); the attempt limit was reached", audit: .failed)
        }
        var next = now.addingTimeInterval(
            DeliveryTiming.backoff(
                attempt: attempt, baseSeconds: limits.baseBackoffSeconds, maxSeconds: limits.maxBackoffSeconds,
                random: random()))
        if let retryAfter, retryAfter > next { next = retryAfter }
        if let validUntil = claimed.validUntil, next >= validUntil {
            return try finish(
                claimed, state: .failed, reason: "\(reason); no retry is possible before it expires", audit: .failed)
        }
        let saved = try updateClaimed(claimed) { delivery in
            if var last = delivery.attempts.popLast() {
                last.finishedAt = now
                last.result = reason
                delivery.attempts.append(last)
            }
            delivery.state = .pending
            delivery.stateReason = reason
            delivery.nextAttemptAt = next
            delivery.leaseExpiresAt = nil
            return nil
        }
        return saved == nil ? .leaseLost : .retrying(at: next)
    }

    func record(_ result: TransportResult, for submitting: Delivery, owner: OwnerSettings) throws -> ProcessOutcome {
        switch result {
        case .accepted(let reference):
            return try finish(
                submitting, state: .acceptedByProvider, reason: "accepted by the provider", audit: .succeeded,
                providerReference: reference)
        case .confirmedDelivered(let reference):
            return try finish(
                submitting, state: .confirmedDelivered, reason: "confirmed by the transport", audit: .succeeded,
                providerReference: reference)
        case .capturedDryRun(let summary):
            return try finish(submitting, state: .capturedDryRun, reason: summary, audit: .simulated)
        case .notSent(let reason):
            return try retryOrFail(submitting, reason: "not sent: \(reason)", retryAfter: nil, owner: owner)
        case .throttled(let retryAfter):
            return try retryOrFail(
                submitting, reason: "throttled by the provider", retryAfter: retryAfter, owner: owner)
        case .temporarilyUnavailable(let reason, let retryAfter):
            return try retryOrFail(
                submitting, reason: "temporarily unavailable: \(reason)", retryAfter: retryAfter, owner: owner)
        case .rejected(let reason, let invalidatesRecipient, let timestamp):
            if invalidatesRecipient, case .device(let deviceID) = submitting.recipient, let tokenFeedback {
                let token = try store.read { try $0.get(DeviceRegistration.self, id: deviceID) }?.pushToken
                if let token {
                    try tokenFeedback.tokenRejected(
                        deviceID: deviceID, token: token.token.revealed, providerTimestamp: timestamp,
                        permanentlyInvalid: timestamp == nil)
                }
            }
            return try finish(submitting, state: .failed, reason: "rejected: \(reason)", audit: .failed)
        case .unknown(let reason):
            return try finish(
                submitting, state: .outcomeUnknown, reason: "\(reason); not resent automatically", audit: .failed)
        }
    }
}
