// Transport boundaries for external actions: email, calls, remote push and local notifications.

import Foundation
import LisaDomain
import LisaRedaction

/// A transport's result. Provider acceptance never means the owner read or answered anything.
public enum TransportResult: Hashable, Sendable {
    case accepted(providerReference: String?)
    case confirmedDelivered(providerReference: String?)
    /// Captured by a dry-run transport; nothing left the host. `summary` records what would have been sent.
    case capturedDryRun(summary: String)
    /// Nothing was sent; retrying may succeed (connection failed before any request byte left).
    case notSent(reason: String)
    case throttled(retryAfter: Date?)
    /// The provider refused the request; retrying the same request will not help.
    case rejected(reason: String, invalidatesRecipient: Bool, providerTimestamp: Date?)
    /// The request may have reached the provider, but the result is unknown. Never retried blindly.
    case unknown(reason: String)
}

/// An outbound email.
public struct EmailEnvelope: Hashable, Sendable {
    public var from: String
    public var fromName: String?
    public var to: [String]
    public var subject: String
    public var textBody: String
    public var messageID: String

    public init(from: String, fromName: String?, to: [String], subject: String, textBody: String, messageID: String) {
        self.from = from
        self.fromName = fromName
        self.to = to
        self.subject = subject
        self.textBody = textBody
        self.messageID = messageID
    }
}

/// An outbound call that speaks a short message.
public struct CallRequest: Hashable, Sendable {
    public var to: String
    public var spokenText: String

    public init(to: String, spokenText: String) {
        self.to = to
        self.spokenText = spokenText
    }
}

/// Neutral notification content for any notification transport.
public struct NotificationPresentation: Hashable, Sendable {
    public var titleKey: String
    public var bodyKey: String
    public var itemTitle: String?
    public var categoryIdentifier: String
    public var threadIdentifier: String
    public var level: InterruptionLevel
    /// Opaque identifiers the device uses to open the item and act on it.
    public var notificationID: String
    public var subjectKind: String
    public var subjectID: String
    public var subjectRevision: Int64

    public init(
        titleKey: String, bodyKey: String, itemTitle: String?, categoryIdentifier: String, threadIdentifier: String,
        level: InterruptionLevel, notificationID: String, subjectKind: String, subjectID: String, subjectRevision: Int64
    ) {
        self.titleKey = titleKey
        self.bodyKey = bodyKey
        self.itemTitle = itemTitle
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.level = level
        self.notificationID = notificationID
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
    }
}

/// A remote push to one registered device.
public struct PushMessage: Hashable, Sendable {
    public var deviceToken: Sensitive<String>
    public var environment: APNsEnvironment
    public var topic: String
    public var presentation: NotificationPresentation
    public var collapseID: String
    /// A stable identifier per delivery, so provider responses correlate with outbox records.
    public var deliveryID: String
    public var expiresAt: Date

    public init(
        deviceToken: Sensitive<String>, environment: APNsEnvironment, topic: String,
        presentation: NotificationPresentation,
        collapseID: String, deliveryID: String, expiresAt: Date
    ) {
        self.deviceToken = deviceToken
        self.environment = environment
        self.topic = topic
        self.presentation = presentation
        self.collapseID = collapseID
        self.deliveryID = deliveryID
        self.expiresAt = expiresAt
    }
}

/// Sends email (production: SMTP over TLS; dry-run: captured).
public protocol EmailTransport: Sendable {
    var mode: DeliveryMode { get }
    func send(_ envelope: EmailEnvelope) async -> TransportResult
}

/// Places calls (production: Twilio; dry-run: captured).
public protocol CallTransport: Sendable {
    var mode: DeliveryMode { get }
    func place(_ call: CallRequest) async -> TransportResult
}

/// Sends remote pushes (production: APNs; dry-run: captured).
public protocol PushTransport: Sendable {
    var mode: DeliveryMode { get }
    func push(_ message: PushMessage) async -> TransportResult
}

/// Presents local notifications on the host's own device (the Mac app's embedded host).
public protocol LocalNotificationTransport: Sendable {
    func present(_ presentation: NotificationPresentation, deliveryID: String) async -> TransportResult
}
