// A reminder occurrence with its rule, due time, acknowledgement, snooze, suppression and escalation state.

import Foundation

/// What a reminder is about.
public enum ReminderSubject: Hashable, Codable, Sendable {
    case task(TaskID)
    case planBlock(planID: PlanID, blockID: String)
    case proposal(ProposalID)
    case occurrenceChange(OccurrenceID)

    public var key: String {
        switch self {
        case .task(let id): "task:\(id.rawValue)"
        case .planBlock(let plan, let block): "block:\(plan.rawValue):\(block)"
        case .proposal(let id): "proposal:\(id.rawValue)"
        case .occurrenceChange(let id): "occurrence:\(id.rawValue)"
        }
    }
}

/// Why a reminder exists (REM-01).
public enum ReminderRule: String, Codable, Sendable {
    case deadlineAhead
    case dateOnlyDeadline
    case overdue
    case planBlockStart
    case proposalFollowUp
    case commitmentChange
}

/// A reminder's lifecycle. Acknowledging never completes the underlying task.
public enum ReminderState: Hashable, Codable, Sendable {
    case scheduled
    case delivered(at: Date)
    case acknowledged(at: Date)
    case snoozed(until: Date)
    case dismissed(at: Date)
    case completed(at: Date)
    case cancelled(reason: String)
    case suppressed(reason: String)

    public var name: String {
        switch self {
        case .scheduled: "scheduled"
        case .delivered: "delivered"
        case .acknowledged: "acknowledged"
        case .snoozed: "snoozed"
        case .dismissed: "dismissed"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .suppressed: "suppressed"
        }
    }

    /// Whether the reminder is finished and must not be delivered again.
    public var isTerminal: Bool {
        switch self {
        case .acknowledged, .dismissed, .completed, .cancelled, .suppressed: true
        case .scheduled, .delivered, .snoozed: false
        }
    }
}

/// An owner action on a reminder.
public enum ReminderAction: String, Codable, Sendable {
    case acknowledge
    case snooze
    case dismiss
    case complete
}

/// One reminder occurrence. `occurrenceKey` is unique, so recomputation never duplicates a reminder.
public struct Reminder: Entity {
    public static let collectionName = "reminders"
    public let id: ReminderID
    public var revision: Revision
    public var updatedAt: Date
    public var subject: ReminderSubject
    public var rule: ReminderRule
    public var dueAt: Date
    public var occurrenceKey: String
    /// The subject's change sequence when the reminder was computed; a later change makes it obsolete.
    public var subjectChangeSequence: Int
    public var title: String
    public var state: ReminderState
    public var urgentDeadline: Bool
    public var createdAt: Date

    public init(
        id: ReminderID = .random(), subject: ReminderSubject, rule: ReminderRule, dueAt: Date, occurrenceKey: String,
        subjectChangeSequence: Int, title: String, urgentDeadline: Bool = false, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.subject = subject
        self.rule = rule
        self.dueAt = dueAt
        self.occurrenceKey = occurrenceKey
        self.subjectChangeSequence = subjectChangeSequence
        self.title = title
        self.state = .scheduled
        self.urgentDeadline = urgentDeadline
        self.createdAt = now
    }

    /// Applies an owner action. Snoozing moves the due time; acknowledging leaves the task open.
    public mutating func apply(_ action: ReminderAction, at now: Date, snoozeMinutes: Int) throws {
        guard !state.isTerminal else {
            throw DomainError.invalidTransition(entity: "reminder", from: state.name, to: action.rawValue)
        }
        switch action {
        case .acknowledge: state = .acknowledged(at: now)
        case .dismiss: state = .dismissed(at: now)
        case .complete: state = .completed(at: now)
        case .snooze:
            let until = now.addingTimeInterval(TimeInterval(max(1, snoozeMinutes) * 60))
            state = .snoozed(until: until)
            dueAt = until
        }
        updatedAt = now
    }

    /// Whether the reminder should be delivered at `now`.
    public func isDue(at now: Date) -> Bool {
        switch state {
        case .scheduled: dueAt <= now
        case .snoozed(let until): until <= now
        default: false
        }
    }
}
