// A delivery-outbox record: intent persisted before any side effect, with attempts, phases and outcomes.

import Foundation

/// How a delivery reaches the owner.
public enum DeliveryChannel: String, Codable, Sendable {
    case email
    case call
    case push
    case localNotification
}

/// Who a delivery is for. Recipients are always the owner's approved addresses, number or paired devices.
public enum DeliveryRecipient: Hashable, Codable, Sendable, CustomStringConvertible {
    case emailAddress(String)
    case phoneNumber(String)
    case device(DeviceID)

    public var description: String {
        switch self {
        case .emailAddress: "email-address"
        case .phoneNumber: "phone-number"
        case .device(let id): "device:\(id.rawValue)"
        }
    }
}

/// Delivery states (REM-03). Provider acceptance never means the owner read or answered anything.
public enum DeliveryState: String, Codable, Sendable, CaseIterable {
    case pending
    case suppressed
    case inProgress
    case acceptedByProvider
    case confirmedDelivered
    case failed
    case outcomeUnknown
    case cancelled
    case capturedDryRun

    /// Whether no further attempt will be made.
    public var isFinal: Bool {
        switch self {
        case .pending, .inProgress: false
        default: true
        }
    }
}

/// The phase of an in-progress attempt. A lease that expires in `submitting` makes the outcome unknown.
public enum AttemptPhase: String, Codable, Sendable {
    case preparing
    case submitting
}

/// Whether a delivery is real or captured by a dry-run transport.
public enum DeliveryMode: String, Codable, Sendable {
    case dryRun
    case live
}

/// What a delivery carries; content is rendered from these references at send time.
public enum DeliveryPayload: Hashable, Codable, Sendable {
    case reminder(ReminderID)
    case brief(BriefID)
    case notification(NotificationID)
}

/// One attempt and its result.
public struct DeliveryAttempt: Hashable, Codable, Sendable {
    public var number: Int
    public var startedAt: Date
    public var phase: AttemptPhase
    public var finishedAt: Date?
    public var result: String?
    public var providerReference: String?

    public init(number: Int, startedAt: Date, phase: AttemptPhase) {
        self.number = number
        self.startedAt = startedAt
        self.phase = phase
        self.finishedAt = nil
        self.result = nil
        self.providerReference = nil
    }
}

/// An outbox record. `idempotencyKey` is unique: the same intent is never recorded twice.
public struct Delivery: Entity {
    public static let collectionName = "deliveries"
    public let id: DeliveryID
    public var revision: Revision
    public var updatedAt: Date
    public var channel: DeliveryChannel
    public var recipient: DeliveryRecipient
    public var payload: DeliveryPayload
    public var idempotencyKey: String
    public var mode: DeliveryMode
    public var state: DeliveryState
    public var stateReason: String?
    public var attempts: [DeliveryAttempt]
    public var nextAttemptAt: Date
    public var leaseExpiresAt: Date?
    public var validUntil: Date?
    public var createdAt: Date

    public init(
        id: DeliveryID = .random(), channel: DeliveryChannel, recipient: DeliveryRecipient, payload: DeliveryPayload,
        idempotencyKey: String, mode: DeliveryMode, notBefore: Date, validUntil: Date?, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.channel = channel
        self.recipient = recipient
        self.payload = payload
        self.idempotencyKey = idempotencyKey
        self.mode = mode
        self.state = .pending
        self.stateReason = nil
        self.attempts = []
        self.nextAttemptAt = notBefore
        self.leaseExpiresAt = nil
        self.validUntil = validUntil
        self.createdAt = now
    }

    /// Whether any attempt reached the submitting phase (bytes may have left the host).
    public var wasEverSubmitted: Bool {
        attempts.contains { $0.phase == .submitting }
    }
}
