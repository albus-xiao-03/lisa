// Rundown, plan-block and brief DTOs (API-02 rundown and brief routes).

import Foundation

/// A deadline: exactly one of `instant` (with the zone it was given in) or `date` (`YYYY-MM-DD`, date-only).
public struct DeadlineDTO: Codable, Hashable, Sendable {
    public var instant: Date?
    public var zone: String?
    public var date: String?

    public init(instant: Date? = nil, zone: String? = nil, date: String? = nil) {
        self.instant = instant
        self.zone = zone
        self.date = date
    }

    /// Whether exactly one form is present and a date is well formed.
    public var isValid: Bool {
        switch (instant, date) {
        case (.some, nil): true
        case (nil, .some(let text)): APIDates.isLocalDate(text)
        default: false
        }
    }
}

/// One block of a rundown.
public struct PlanBlockDTO: Codable, Hashable, Sendable {
    public var blockID: String
    /// `fixedEvent`, `task` or `idea`.
    public var kind: String
    /// `occurrence`, `task` or `idea`.
    public var subjectKind: String
    public var subjectID: String
    public var title: String
    public var start: Date
    public var end: Date
    /// `proposed`, `accepted`, `locked`, `rejected`, `completed` or `deferred`.
    public var state: String
    public var provisional: Bool
    public var explanation: String

    public init(
        blockID: String, kind: String, subjectKind: String, subjectID: String, title: String, start: Date, end: Date,
        state: String, provisional: Bool, explanation: String
    ) {
        self.blockID = blockID
        self.kind = kind
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.title = title
        self.start = start
        self.end = end
        self.state = state
        self.provisional = provisional
        self.explanation = explanation
    }
}

/// An item the planner could not place, with the reason.
public struct UnscheduledItemDTO: Codable, Hashable, Sendable {
    public var subjectKind: String
    public var subjectID: String
    public var title: String
    public var reason: String

    public init(subjectKind: String, subjectID: String, title: String, reason: String) {
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.title = title
        self.reason = reason
    }
}

/// The daily rundown (the stored plan for a local date).
public struct RundownDTO: Codable, Hashable, Sendable {
    public var planID: String
    public var revision: Int64
    public var date: String
    public var zone: String
    public var blocks: [PlanBlockDTO]
    public var unscheduled: [UnscheduledItemDTO]
    public var warnings: [String]
    /// Explanations of what changed since the previous revision.
    public var changes: [String]
    public var availabilityUncertain: Bool
    public var computedAt: Date

    public init(
        planID: String, revision: Int64, date: String, zone: String, blocks: [PlanBlockDTO],
        unscheduled: [UnscheduledItemDTO], warnings: [String], changes: [String], availabilityUncertain: Bool,
        computedAt: Date
    ) {
        self.planID = planID
        self.revision = revision
        self.date = date
        self.zone = zone
        self.blocks = blocks
        self.unscheduled = unscheduled
        self.warnings = warnings
        self.changes = changes
        self.availabilityUncertain = availabilityUncertain
        self.computedAt = computedAt
    }
}

/// Owner actions on a plan block.
public enum PlanBlockActionKind: String, Codable, Hashable, Sendable, CaseIterable {
    case accept
    case lock
    case reject
    case complete
    case `defer`
    /// Gives the block a new `start` and `end` on the plan's local day; it becomes `locked` there, and the host plans
    /// the rest of the day around it. Hosts that predate it refuse it as a body that does not match the schema (400).
    case move
}

/// `POST /v1/plans/{planID}/blocks/{blockID}/actions`.
public struct PlanBlockActionRequest: Codable, Hashable, Sendable {
    public var action: PlanBlockActionKind
    /// The plan revision the owner saw.
    public var expectedRevision: Int64
    /// For `move`, and required by it: the block's new start, a whole minute on the plan's local day. Never sent with
    /// other actions.
    public var start: Date?
    /// For `move`, and required by it: the block's new end, a whole minute after `start` on the same local day (at
    /// the latest the midnight that ends it). Never sent with other actions.
    public var end: Date?

    public init(action: PlanBlockActionKind, expectedRevision: Int64, start: Date? = nil, end: Date? = nil) {
        self.action = action
        self.expectedRevision = expectedRevision
        self.start = start
        self.end = end
    }
}

/// A record a brief item cites.
public struct SourceReferenceDTO: Codable, Hashable, Sendable {
    public var recordKind: String
    public var recordID: String
    public var originalURL: String?

    public init(recordKind: String, recordID: String, originalURL: String? = nil) {
        self.recordKind = recordKind
        self.recordID = recordID
        self.originalURL = originalURL
    }
}

/// One item of a brief.
public struct BriefItemDTO: Codable, Hashable, Sendable {
    /// `commitments`, `deadlines`, `email`, `events`, `ideas`, `news`, `changes` or `sourceHealth`.
    public var section: String
    public var text: String
    public var spokenText: String
    public var references: [SourceReferenceDTO]
    public var material: Bool
    public var uncertainty: String?

    public init(
        section: String, text: String, spokenText: String, references: [SourceReferenceDTO], material: Bool,
        uncertainty: String?
    ) {
        self.section = section
        self.text = text
        self.spokenText = spokenText
        self.references = references
        self.material = material
        self.uncertainty = uncertainty
    }
}

/// The brief for a local date.
public struct BriefDTO: Codable, Hashable, Sendable {
    public var briefID: String
    public var revision: Int64
    public var date: String
    public var zone: String
    public var version: Int
    /// `current`, `stale` or `failed`; a failed regeneration keeps the last good content.
    public var state: String
    public var text: String
    public var spokenText: String
    public var items: [BriefItemDTO]
    public var omittedCount: Int
    public var generatedAt: Date
    public var estimatedSpokenSeconds: Int
    /// True when the brief was composed from templates without a model.
    public var templateOnly: Bool
    public var lastFailure: String?

    public init(
        briefID: String, revision: Int64, date: String, zone: String, version: Int, state: String, text: String,
        spokenText: String, items: [BriefItemDTO], omittedCount: Int, generatedAt: Date, estimatedSpokenSeconds: Int,
        templateOnly: Bool, lastFailure: String?
    ) {
        self.briefID = briefID
        self.revision = revision
        self.date = date
        self.zone = zone
        self.version = version
        self.state = state
        self.text = text
        self.spokenText = spokenText
        self.items = items
        self.omittedCount = omittedCount
        self.generatedAt = generatedAt
        self.estimatedSpokenSeconds = estimatedSpokenSeconds
        self.templateOnly = templateOnly
        self.lastFailure = lastFailure
    }
}

/// `POST /v1/briefs/regenerate`. Omitting the date regenerates today's brief.
public struct RegenerateBriefRequest: Codable, Hashable, Sendable {
    public var date: String?

    public init(date: String? = nil) {
        self.date = date
    }
}
