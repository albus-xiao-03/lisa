// A notification occurrence decided by the host, with its identity, revision basis, validity and level.

import Foundation

/// Notification categories; each maps to a device-side category with its own actions.
public enum NotificationCategory: String, Codable, Sendable, CaseIterable {
    case reminder
    case overdue
    case planBlock
    case eventProposal
    case commitmentChange
    case brief
}

/// Interruption levels. Critical is deliberately absent: Lisa never uses Critical Alerts.
public enum InterruptionLevel: String, Codable, Sendable {
    case passive
    case active
    case timeSensitive
}

/// What a notification is about.
public enum NotificationSubject: Hashable, Codable, Sendable {
    case reminder(ReminderID)
    case task(TaskID)
    case occurrence(OccurrenceID)
    case proposal(ProposalID)
    case brief(BriefID)

    /// A stable key, used in occurrence identities and collapse keys.
    public var key: String {
        switch self {
        case .reminder(let id): "reminder:\(id.rawValue)"
        case .task(let id): "task:\(id.rawValue)"
        case .occurrence(let id): "occurrence:\(id.rawValue)"
        case .proposal(let id): "proposal:\(id.rawValue)"
        case .brief(let id): "brief:\(id.rawValue)"
        }
    }
}

/// The lifecycle of a notification occurrence.
public enum NotificationOccurrenceState: String, Codable, Sendable {
    /// Deliveries exist and may still be attempted.
    case active
    /// Replaced by a newer change before any delivery was submitted.
    case coalesced
    /// No longer the latest change at send time, and nothing was submitted.
    case superseded
    /// The subject was resolved (acknowledged, completed or cancelled) before delivery.
    case resolved
    /// The validity window passed.
    case expired
}

/// One notification occurrence (§6.4 of the plan).
///
/// Identity rules:
/// - Reminders: the reminder occurrence key.
/// - Important changes: the subject plus its change sequence, so every later material change is a new occurrence,
///   even after an earlier change was delivered.
/// - Brief availability: the local date and time zone; one notification per daily brief is an explicit policy.
public struct NotificationIntent: Entity {
    public static let collectionName = "notifications"
    public let id: NotificationID
    public var revision: Revision
    public var updatedAt: Date
    /// Unique occurrence identity, such as `commitmentChange:occurrence:<id>:3`.
    public var occurrenceKey: String
    public var category: NotificationCategory
    public var subject: NotificationSubject
    /// The subject's change sequence this occurrence was based on.
    public var changeSequence: Int
    /// The device-side collapse key: per subject and category for changes, per occurrence for reminders.
    public var collapseKey: String
    public var interruptionLevel: InterruptionLevel
    /// A short item title, used only for devices that opted in to titles.
    public var titleHint: String?
    public var createdAt: Date
    public var validUntil: Date
    public var state: NotificationOccurrenceState

    public init(
        id: NotificationID = .random(), occurrenceKey: String, category: NotificationCategory,
        subject: NotificationSubject, changeSequence: Int, collapseKey: String, interruptionLevel: InterruptionLevel,
        titleHint: String?, validUntil: Date, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.occurrenceKey = occurrenceKey
        self.category = category
        self.subject = subject
        self.changeSequence = changeSequence
        self.collapseKey = collapseKey
        self.interruptionLevel = interruptionLevel
        self.titleHint = titleHint
        self.createdAt = now
        self.validUntil = validUntil
        self.state = .active
    }

    /// The occurrence identity for an important change.
    public static func changeKey(subject: NotificationSubject, changeSequence: Int) -> String {
        "\(NotificationCategory.commitmentChange.rawValue):\(subject.key):\(changeSequence)"
    }

    /// The collapse key for an important change: the same for every change to one subject, so a newer change
    /// replaces an older one on the device instead of stacking.
    public static func changeCollapseKey(subject: NotificationSubject) -> String {
        "\(NotificationCategory.commitmentChange.rawValue):\(subject.key)"
    }
}
