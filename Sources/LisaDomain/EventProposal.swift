// An extracted event that may be missing from the owner's calendars, with its match and review state.

import Foundation
import LisaTime

/// When a proposed event would happen, as far as the evidence says.
public enum ProposedTiming: Hashable, Codable, Sendable {
    case timed(start: Date, end: Date?, zone: TimeZoneID?)
    case dateOnly(LocalDate)
    case unknown
}

/// How a proposal relates to the subscribed calendars (EVENT-01).
public enum ProposalMatchState: Hashable, Codable, Sendable {
    case needsClarification(String)
    case notFound
    case possibleMatch(OccurrenceID, reasons: [String])
    case matched(OccurrenceID)
    case dismissed
    case ownerReportsAdded(at: Date)

    /// A short state name for display and filtering.
    public var name: String {
        switch self {
        case .needsClarification: "needsClarification"
        case .notFound: "notFound"
        case .possibleMatch: "possibleMatch"
        case .matched: "matched"
        case .dismissed: "dismissed"
        case .ownerReportsAdded: "ownerReportsAdded"
        }
    }

    /// Whether the owner still needs to act on it.
    public var isUnresolved: Bool {
        switch self {
        case .needsClarification, .notFound, .possibleMatch: true
        case .matched, .dismissed, .ownerReportsAdded: false
        }
    }
}

/// An owner's review action on a proposal.
public enum ProposalAction: Hashable, Codable, Sendable {
    case confirmMatch(OccurrenceID)
    case dismiss
    case correct(title: String?, timing: ProposedTiming?, location: String?)
    case reportAdded
}

/// An event proposal extracted from evidence. Lisa never adds it to a calendar herself.
public struct EventProposal: Entity {
    public static let collectionName = "proposals"
    public let id: ProposalID
    public var revision: Revision
    public var updatedAt: Date
    public var title: String
    public var timing: ProposedTiming
    public var location: String?
    public var participants: [String]
    public var evidenceIDs: [EvidenceID]
    /// Uncertainties the extraction could not settle, shown to the owner.
    public var uncertainty: [String]
    public var matchState: ProposalMatchState
    public var ownerCorrected: Set<CorrectableField>
    public var createdAt: Date
    public var lastFollowUpAt: Date?
    public var changeSequence: Int

    public init(
        id: ProposalID = .random(), title: String, timing: ProposedTiming, location: String? = nil,
        participants: [String] = [], evidenceIDs: [EvidenceID], uncertainty: [String] = [], now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.title = title
        self.timing = timing
        self.location = location
        self.participants = participants
        self.evidenceIDs = evidenceIDs
        self.uncertainty = uncertainty
        self.matchState = timing == .unknown ? .needsClarification("the date or time is missing") : .notFound
        self.ownerCorrected = []
        self.createdAt = now
        self.lastFollowUpAt = nil
        self.changeSequence = 0
    }

    /// Applies an owner review action.
    public mutating func apply(_ action: ProposalAction, at now: Date) throws {
        switch action {
        case .confirmMatch(let occurrence):
            guard matchState != .dismissed else {
                throw DomainError.invalidTransition(entity: "proposal", from: matchState.name, to: "matched")
            }
            matchState = .matched(occurrence)
        case .dismiss:
            matchState = .dismissed
        case .correct(let title, let timing, let location):
            if let title {
                self.title = title
                ownerCorrected.insert(.title)
            }
            if let timing {
                self.timing = timing
                ownerCorrected.insert(.timing)
            }
            if let location {
                self.location = location
                ownerCorrected.insert(.location)
            }
            if case .needsClarification = matchState, self.timing != .unknown {
                matchState = .notFound
            }
        case .reportAdded:
            guard matchState.isUnresolved else {
                throw DomainError.invalidTransition(entity: "proposal", from: matchState.name, to: "ownerReportsAdded")
            }
            matchState = .ownerReportsAdded(at: now)
        }
        updatedAt = now
        changeSequence += 1
    }
}
