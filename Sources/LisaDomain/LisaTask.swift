// A task or commitment, with confirmation state, deadline precision, evidence and owner corrections.

import Foundation
import LisaTime

/// A task's lifecycle state.
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case open
    case inProgress
    case blocked
    case completed
    case cancelled

    /// Whether the task still needs work.
    public var isActive: Bool { self == .open || self == .inProgress || self == .blocked }
}

/// Explicit task priority.
public enum TaskPriority: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case normal
    case high
    case urgent

    /// Higher is more important.
    public var rank: Int {
        switch self {
        case .low: 0
        case .normal: 1
        case .high: 2
        case .urgent: 3
        }
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether the priority counts as high for urgency rules.
    public var isHigh: Bool { rank >= TaskPriority.high.rank }
}

/// Whether the owner confirmed an item, it is only possible, or it is merely informational.
public enum Confirmation: String, Codable, Sendable {
    case confirmed
    case possible
    case informational
}

/// How a task came to exist.
public enum TaskOrigin: String, Codable, Sendable {
    case manual
    case extracted
    case capture
}

/// Fields that the owner can correct; corrected fields are never overwritten by later model suggestions.
public enum CorrectableField: String, Codable, Sendable, CaseIterable {
    case title
    case deadline
    case priority
    case duration
    case confirmation
    case status
    case timing
    case location
    case participants
}

/// A task or commitment.
public struct LisaTask: Entity {
    public static let collectionName = "tasks"
    public let id: TaskID
    public var revision: Revision
    public var updatedAt: Date
    public var title: String
    public var notes: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var deadline: Deadline?
    /// Present when the deadline phrase could not be resolved; the deadline then stays empty until clarified.
    public var unresolvedDeadlineText: String?
    public var estimatedMinutes: Int?
    public var splittable: Bool
    public var confirmation: Confirmation
    public var origin: TaskOrigin
    public var evidenceIDs: [EvidenceID]
    /// For an extracted task, the title its extraction gave it. Reprocessing the same evidence recognizes the task by
    /// this title rather than the current one, so a task the owner renamed is updated, never duplicated (D-33).
    public var extractedTitle: String?
    public var ownerCorrected: Set<CorrectableField>
    public var createdAt: Date
    public var completedAt: Date?
    /// Increases with every material change (deadline, status, title or priority) for notification identities.
    public var changeSequence: Int

    public init(
        id: TaskID = .random(), title: String, notes: String = "", priority: TaskPriority = .normal,
        deadline: Deadline? = nil, estimatedMinutes: Int? = nil, splittable: Bool = false,
        confirmation: Confirmation, origin: TaskOrigin, evidenceIDs: [EvidenceID] = [], now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.title = title
        self.notes = notes
        self.status = .open
        self.priority = priority
        self.deadline = deadline
        self.unresolvedDeadlineText = nil
        self.estimatedMinutes = estimatedMinutes
        self.splittable = splittable
        self.confirmation = confirmation
        self.origin = origin
        self.evidenceIDs = evidenceIDs
        self.extractedTitle = nil
        self.ownerCorrected = []
        self.createdAt = now
        self.completedAt = nil
        self.changeSequence = 0
    }

    /// Moves the task to `target`, enforcing the lifecycle.
    public mutating func transition(to target: TaskStatus, at now: Date) throws {
        let allowed: Set<TaskStatus> =
            switch status {
            case .open: [.inProgress, .blocked, .completed, .cancelled]
            case .inProgress: [.open, .blocked, .completed, .cancelled]
            case .blocked: [.open, .inProgress, .completed, .cancelled]
            case .completed, .cancelled: [.open]
            }
        guard allowed.contains(target) else {
            throw DomainError.invalidTransition(entity: "task", from: status.rawValue, to: target.rawValue)
        }
        status = target
        completedAt = target == .completed ? now : nil
        updatedAt = now
        changeSequence += 1
    }

    /// Whether the task is a confirmed commitment that may constrain planning and drive reminders.
    public var isConfirmedCommitment: Bool { confirmation == .confirmed }
}
