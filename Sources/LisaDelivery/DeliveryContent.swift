// What a claimed delivery carries, decided at send time by the service that owns its payload.

import Foundation
import LisaDomain
import LisaPolicy

/// Notification content before the device-specific choices (title visibility, Time Sensitive acceptance) are applied.
public struct NotificationDraft: Hashable, Sendable {
    public var category: NotificationCategory
    public var level: InterruptionLevel
    public var content: NotificationContent
    public var notificationID: String
    public var subjectKind: String
    public var subjectID: String
    public var subjectRevision: Int64
    /// The raw collapse key; the APNs adapter sends a fixed-length digest of it.
    public var collapseKey: String

    public init(
        category: NotificationCategory, level: InterruptionLevel, content: NotificationContent, notificationID: String,
        subjectKind: String, subjectID: String, subjectRevision: Int64, collapseKey: String
    ) {
        self.category = category
        self.level = level
        self.content = content
        self.notificationID = notificationID
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.collapseKey = collapseKey
    }
}

/// What the payload's owner says a delivery should carry now.
public enum PreparedDelivery: Sendable {
    case email(subject: String, textBody: String)
    /// A call with the facts the call gate needs. The outbox adds today's call counts and evaluates CALL-01.
    case call(spokenText: String, gate: CallContext)
    case notification(NotificationDraft)
    /// The subject was resolved, superseded or is otherwise stale: the delivery is suppressed with this reason.
    case notEligible(reason: String)
}

/// Implemented by the service that owns each payload kind (LisaAgenda for reminders, briefs and notification intents).
public protocol DeliveryContentProvider: Sendable {
    func prepare(_ delivery: Delivery, settings: OwnerSettings, now: Date) throws -> PreparedDelivery
}
