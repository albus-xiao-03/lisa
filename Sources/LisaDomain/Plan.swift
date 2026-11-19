// A daily rundown: fixed events, Lisa's proposed blocks, unscheduled items and the basis the plan was made on.

import Foundation
import LisaTime

/// What a plan block represents.
public enum PlanBlockKind: String, Codable, Sendable {
    case fixedEvent
    case task
    case idea
}

/// The owner-facing state of a block. Fixed events are always `locked`.
public enum PlanBlockState: String, Codable, Sendable {
    case proposed
    case accepted
    case locked
    case rejected
    case completed
    case deferred
}

/// The record a block refers to.
public enum PlanSubject: Hashable, Codable, Sendable {
    case occurrence(OccurrenceID)
    case task(TaskID)
    case idea(IdeaID)

    /// A stable text key, used for stable ordering and for remembering rejected suggestions.
    public var key: String {
        switch self {
        case .occurrence(let id): "occurrence:\(id.rawValue)"
        case .task(let id): "task:\(id.rawValue)"
        case .idea(let id): "idea:\(id.rawValue)"
        }
    }
}

/// A block in the rundown.
public struct PlanBlock: Hashable, Codable, Sendable {
    public var blockID: String
    public var kind: PlanBlockKind
    public var subject: PlanSubject
    public var title: String
    public var range: TimeRange
    public var state: PlanBlockState
    /// Proposed while availability was uncertain; never used for automatic escalation.
    public var provisional: Bool
    public var explanation: String

    public init(
        blockID: String, kind: PlanBlockKind, subject: PlanSubject, title: String, range: TimeRange,
        state: PlanBlockState, provisional: Bool, explanation: String
    ) {
        self.blockID = blockID
        self.kind = kind
        self.subject = subject
        self.title = title
        self.range = range
        self.state = state
        self.provisional = provisional
        self.explanation = explanation
    }
}

/// Work that could not be placed, with the reason.
public struct UnscheduledItem: Hashable, Codable, Sendable {
    public var subject: PlanSubject
    public var title: String
    public var reason: String

    public init(subject: PlanSubject, title: String, reason: String) {
        self.subject = subject
        self.title = title
        self.reason = reason
    }
}

/// A suggestion the owner rejected, remembered with the inputs it was based on so it is not reintroduced without a
/// relevant change.
public struct RejectedSuggestion: Hashable, Codable, Sendable {
    public var subjectKey: String
    public var inputFingerprint: String

    public init(subjectKey: String, inputFingerprint: String) {
        self.subjectKey = subjectKey
        self.inputFingerprint = inputFingerprint
    }
}

/// What the plan was based on (PLAN-05).
public struct PlanBasis: Hashable, Codable, Sendable {
    /// Per source: the last successful refresh time and freshness at planning time.
    public var sourceFreshness: [String: SourceFreshness]
    public var sourceRefreshedAt: [String: Date]
    public var availabilityUncertain: Bool
    public var computedAt: Date

    public init(
        sourceFreshness: [String: SourceFreshness], sourceRefreshedAt: [String: Date], availabilityUncertain: Bool,
        computedAt: Date
    ) {
        self.sourceFreshness = sourceFreshness
        self.sourceRefreshedAt = sourceRefreshedAt
        self.availabilityUncertain = availabilityUncertain
        self.computedAt = computedAt
    }
}

/// The rundown for one local date in one time zone, with explicit revisions.
public struct Plan: Entity {
    public static let collectionName = "plans"
    public let id: PlanID
    public var revision: Revision
    public var updatedAt: Date
    public var localDate: LocalDate
    public var zone: TimeZoneID
    public var blocks: [PlanBlock]
    public var unscheduled: [UnscheduledItem]
    public var basis: PlanBasis
    public var warnings: [String]
    /// Explanations of what changed since the previous revision.
    public var changes: [String]
    public var rejectedSuggestions: [RejectedSuggestion]

    public init(
        id: PlanID = .random(), localDate: LocalDate, zone: TimeZoneID, blocks: [PlanBlock],
        unscheduled: [UnscheduledItem], basis: PlanBasis, warnings: [String], now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.localDate = localDate
        self.zone = zone
        self.blocks = blocks
        self.unscheduled = unscheduled
        self.basis = basis
        self.warnings = warnings
        self.changes = []
        self.rejectedSuggestions = []
    }

    /// The natural key: one plan per local date and time zone.
    public static func key(date: LocalDate, zone: TimeZoneID) -> String {
        "\(date.iso)|\(zone.identifier)"
    }
}
