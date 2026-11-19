// One concrete occurrence of a subscribed calendar event, with timing semantics, status and availability.

import Foundation
import LisaTime

/// When an occurrence happens, preserving the source's time semantics.
public enum OccurrenceTiming: Hashable, Codable, Sendable {
    /// A timed occurrence. `zone` is the source zone (nil for UTC); `floating` marks a configured floating-time
    /// interpretation.
    case timed(start: Date, end: Date, zone: TimeZoneID?, floating: Bool)
    /// An all-day occurrence covering local dates `[first, endExclusive)`.
    case allDay(first: LocalDate, endExclusive: LocalDate)
}

/// The occurrence's status in the source calendar.
public enum OccurrenceStatus: String, Codable, Sendable {
    case confirmed
    case tentative
    case cancelled
}

/// Whether an occurrence blocks time.
public enum Availability: String, Codable, Sendable {
    case busy
    case free
}

/// A concrete calendar occurrence. Recurring events are expanded into bounded occurrences.
public struct CalendarOccurrence: Entity {
    public static let collectionName = "occurrences"
    public let id: OccurrenceID
    public var revision: Revision
    public var updatedAt: Date
    public var sourceID: SourceID
    public var uid: String
    /// Identifies the occurrence within its series (the original start, as RECURRENCE-ID would name it).
    public var occurrenceKey: String
    public var title: String
    public var location: String?
    public var timing: OccurrenceTiming
    public var status: OccurrenceStatus
    public var availability: Availability
    public var sequence: Int
    public var sourceLastModified: Date?
    /// Visible warnings, such as an unsupported recurrence construct.
    public var warnings: [String]
    public var evidenceID: EvidenceID?
    /// The refresh in which the occurrence was last seen.
    public var lastSeenRefreshAt: Date
    /// Increases with every material change (time, status, availability, title or location).
    public var changeSequence: Int

    public init(
        id: OccurrenceID = .random(), sourceID: SourceID, uid: String, occurrenceKey: String, title: String,
        location: String?, timing: OccurrenceTiming, status: OccurrenceStatus, availability: Availability,
        sequence: Int, sourceLastModified: Date?, warnings: [String], evidenceID: EvidenceID?, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.sourceID = sourceID
        self.uid = uid
        self.occurrenceKey = occurrenceKey
        self.title = title
        self.location = location
        self.timing = timing
        self.status = status
        self.availability = availability
        self.sequence = sequence
        self.sourceLastModified = sourceLastModified
        self.warnings = warnings
        self.evidenceID = evidenceID
        self.lastSeenRefreshAt = now
        self.changeSequence = 0
    }

    /// The instants this occurrence covers when planning in `zone`.
    public func range(in zone: TimeZone) -> TimeRange {
        switch timing {
        case .timed(let start, let end, _, _):
            return TimeRange(uncheckedStart: start, end: max(start, end))
        case .allDay(let first, let endExclusive):
            let start = ZoneRules.startOfDay(first, in: zone)
            let end = ZoneRules.startOfDay(max(endExclusive, first.adding(days: 1)), in: zone)
            return TimeRange(uncheckedStart: start, end: max(start, end))
        }
    }

    /// Whether the occurrence blocks time: busy and not cancelled.
    public var blocksTime: Bool {
        status != .cancelled && availability == .busy
    }

    /// Whether `other` differs in a way the owner should hear about.
    public func isMateriallyDifferent(from other: CalendarOccurrence) -> Bool {
        timing != other.timing || status != other.status || availability != other.availability
            || title != other.title || location != other.location
    }
}
