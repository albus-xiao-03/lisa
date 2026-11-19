// The grounded facts a brief is composed from, each tied to the record it came from.

import Foundation
import LisaDomain
import LisaTime

/// The state of one source at brief time.
public struct SourceStatusLine: Hashable, Sendable {
    public var sourceID: SourceID
    public var name: String
    public var kind: SourceKind
    /// True when the last refresh succeeded and is fresh; false when it failed or is stale.
    public var checked: Bool
    public var detail: String?

    public init(sourceID: SourceID, name: String, kind: SourceKind, checked: Bool, detail: String?) {
        self.sourceID = sourceID
        self.name = name
        self.kind = kind
        self.checked = checked
        self.detail = detail
    }
}

/// An email that needs the owner's attention, with the deterministic or validated reason.
public struct EmailAttention: Sendable {
    public var email: EmailMessage
    public var reason: String

    public init(email: EmailMessage, reason: String) {
        self.email = email
        self.reason = reason
    }
}

/// A selected news item and why.
public struct BriefNews: Sendable {
    public var item: NewsItem
    public var reason: String
    public var sourceName: String

    public init(item: NewsItem, reason: String, sourceName: String) {
        self.item = item
        self.reason = reason
        self.sourceName = sourceName
    }
}

/// A material change since the previous brief.
public struct BriefChange: Hashable, Sendable {
    public var text: String
    public var spokenText: String
    public var references: [SourceReference]

    public init(text: String, spokenText: String, references: [SourceReference]) {
        self.text = text
        self.spokenText = spokenText
        self.references = references
    }
}

/// Everything one brief is built from.
public struct BriefInput: Sendable {
    public var date: LocalDate
    public var zone: TimeZoneID
    public var now: Date
    public var commitments: [CalendarOccurrence]
    /// Confirmed active tasks with deadlines that are overdue, today or within two days.
    public var tasks: [LisaTask]
    /// Extracted tasks that are not confirmed; shown as possible.
    public var possibleTasks: [LisaTask]
    public var emails: [EmailAttention]
    public var proposals: [EventProposal]
    public var ideaBlocks: [PlanBlock]
    public var news: [BriefNews]
    public var changes: [BriefChange]
    public var sources: [SourceStatusLine]
    public var availabilityUncertain: Bool
    public var settings: BriefSettings

    public init(
        date: LocalDate, zone: TimeZoneID, now: Date, commitments: [CalendarOccurrence], tasks: [LisaTask],
        possibleTasks: [LisaTask], emails: [EmailAttention], proposals: [EventProposal], ideaBlocks: [PlanBlock],
        news: [BriefNews], changes: [BriefChange], sources: [SourceStatusLine], availabilityUncertain: Bool,
        settings: BriefSettings
    ) {
        self.date = date
        self.zone = zone
        self.now = now
        self.commitments = commitments
        self.tasks = tasks
        self.possibleTasks = possibleTasks
        self.emails = emails
        self.proposals = proposals
        self.ideaBlocks = ideaBlocks
        self.news = news
        self.changes = changes
        self.sources = sources
        self.availabilityUncertain = availabilityUncertain
        self.settings = settings
    }
}
