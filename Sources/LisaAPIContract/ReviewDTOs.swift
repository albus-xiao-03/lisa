// Event-proposal, reminder and notification-action DTOs (API-02 review and reminder routes, NOTIFY-05).

import Foundation

/// The proposed timing of an event: an instant range, a local date, or unknown.
public struct ProposedTimingDTO: Codable, Hashable, Sendable {
    public var start: Date?
    public var end: Date?
    public var zone: String?
    /// `YYYY-MM-DD` for a date-only proposal.
    public var date: String?

    public init(start: Date? = nil, end: Date? = nil, zone: String? = nil, date: String? = nil) {
        self.start = start
        self.end = end
        self.zone = zone
        self.date = date
    }

    public var isUnknown: Bool { start == nil && date == nil }
}

/// How a proposal relates to the calendar.
public struct MatchStateDTO: Codable, Hashable, Sendable {
    /// `needsClarification`, `notFound`, `possibleMatch`, `matched`, `dismissed` or `ownerReportsAdded`.
    public var state: String
    public var occurrenceID: String?
    public var reasons: [String]
    public var detail: String?

    public init(state: String, occurrenceID: String? = nil, reasons: [String] = [], detail: String? = nil) {
        self.state = state
        self.occurrenceID = occurrenceID
        self.reasons = reasons
        self.detail = detail
    }
}

/// An event proposal derived from a message.
public struct EventProposalDTO: Codable, Hashable, Sendable {
    public var id: String
    public var revision: Int64
    public var title: String
    public var timing: ProposedTimingDTO
    public var location: String?
    public var participants: [String]
    public var uncertainty: [String]
    public var match: MatchStateDTO
    public var evidenceCount: Int
    public var createdAt: Date

    public init(
        id: String, revision: Int64, title: String, timing: ProposedTimingDTO, location: String?,
        participants: [String], uncertainty: [String], match: MatchStateDTO, evidenceCount: Int, createdAt: Date
    ) {
        self.id = id
        self.revision = revision
        self.title = title
        self.timing = timing
        self.location = location
        self.participants = participants
        self.uncertainty = uncertainty
        self.match = match
        self.evidenceCount = evidenceCount
        self.createdAt = createdAt
    }
}

/// Owner review actions on a proposal.
public enum ProposalActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case confirmMatch
    case dismiss
    case correct
    case reportAdded
}

/// `POST /v1/event-proposals/{id}/actions`.
public struct ProposalActionRequest: Codable, Hashable, Sendable {
    public var action: ProposalActionKind
    public var expectedRevision: Int64
    /// Required for `confirmMatch`.
    public var occurrenceID: String?
    /// Corrections for `correct`; omitted values are unchanged.
    public var title: String?
    public var timing: ProposedTimingDTO?
    public var location: String?

    public init(
        action: ProposalActionKind, expectedRevision: Int64, occurrenceID: String? = nil, title: String? = nil,
        timing: ProposedTimingDTO? = nil, location: String? = nil
    ) {
        self.action = action
        self.expectedRevision = expectedRevision
        self.occurrenceID = occurrenceID
        self.title = title
        self.timing = timing
        self.location = location
    }
}

/// A reminder.
public struct ReminderDTO: Codable, Hashable, Sendable {
    public var id: String
    public var revision: Int64
    /// `task`, `planBlock`, `proposal` or `occurrence`.
    public var subjectKind: String
    public var subjectID: String
    /// `deadlineAhead`, `dateOnlyDeadline`, `overdue`, `planBlockStart`, `proposalFollowUp` or `commitmentChange`.
    public var rule: String
    public var dueAt: Date
    public var title: String
    /// `scheduled`, `delivered`, `acknowledged`, `snoozed`, `dismissed`, `completed`, `cancelled` or `suppressed`.
    public var state: String
    public var stateDetail: String?
    public var snoozedUntil: Date?
    public var urgentDeadline: Bool

    public init(
        id: String, revision: Int64, subjectKind: String, subjectID: String, rule: String, dueAt: Date, title: String,
        state: String, stateDetail: String?, snoozedUntil: Date?, urgentDeadline: Bool
    ) {
        self.id = id
        self.revision = revision
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.rule = rule
        self.dueAt = dueAt
        self.title = title
        self.state = state
        self.stateDetail = stateDetail
        self.snoozedUntil = snoozedUntil
        self.urgentDeadline = urgentDeadline
    }
}

/// Owner actions on a reminder or a notification. Acknowledging never completes the underlying task.
public enum ReminderActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case acknowledge
    case snooze
    case dismiss
    case complete
}

/// `POST /v1/reminders/{id}/actions`.
public struct ReminderActionRequest: Codable, Hashable, Sendable {
    public var action: ReminderActionKind
    /// When present, the action is refused if the reminder changed since.
    public var expectedRevision: Int64?

    public init(action: ReminderActionKind, expectedRevision: Int64? = nil) {
        self.action = action
        self.expectedRevision = expectedRevision
    }
}

/// `POST /v1/notifications/{id}/actions`: an action chosen on a delivered notification, identified by the payload's
/// notification ID. Change and brief notifications accept only `acknowledge` and `dismiss`.
public struct NotificationActionRequest: Codable, Hashable, Sendable {
    public var action: ReminderActionKind

    public init(action: ReminderActionKind) {
        self.action = action
    }
}

/// The result of a notification action.
public struct NotificationActionResult: Codable, Hashable, Sendable {
    public var notificationID: String
    public var action: ReminderActionKind
    /// The reminder after the action, when the notification was about a reminder.
    public var reminder: ReminderDTO?

    public init(notificationID: String, action: ReminderActionKind, reminder: ReminderDTO?) {
        self.notificationID = notificationID
        self.action = action
        self.reminder = reminder
    }
}
