// The result of expanding a calendar: concrete occurrences plus visible warnings and an uncertainty flag.

import Foundation
import LisaTime

/// The time span of an expanded occurrence.
public enum OccurrenceTimes: Hashable, Sendable {
    /// A timed occurrence. `tzid` names the source zone (nil for UTC); `floating` marks the configured
    /// floating-time interpretation.
    case timed(start: Date, end: Date, tzid: String?, floating: Bool)
    /// An all-day occurrence covering `[first, endExclusive)`.
    case allDay(first: LocalDate, endExclusive: LocalDate)
}

/// An event's status.
public enum EventStatus: String, Hashable, Sendable {
    case confirmed
    case tentative
    case cancelled
}

/// One concrete occurrence.
public struct ExpandedOccurrence: Hashable, Sendable {
    public var uid: String
    /// The original start of the occurrence (`yyyyMMddTHHmmssZ` or `yyyyMMdd`), which RECURRENCE-ID refers to.
    public var occurrenceKey: String
    public var title: String
    public var location: String?
    public var notes: String?
    public var times: OccurrenceTimes
    public var status: EventStatus
    public var transparent: Bool
    public var sequence: Int
    public var lastModified: Date?
    public var warnings: [String]
}

/// A visible problem found while expanding.
public struct CalendarWarning: Hashable, Sendable {
    public var uid: String?
    public var message: String
    /// Whether planning must treat this calendar's availability as uncertain.
    public var makesAvailabilityUncertain: Bool

    public init(uid: String?, message: String, makesAvailabilityUncertain: Bool) {
        self.uid = uid
        self.message = message
        self.makesAvailabilityUncertain = makesAvailabilityUncertain
    }
}

/// The expanded contents of one calendar within a window.
public struct ExpandedCalendar: Sendable {
    public var name: String?
    public var occurrences: [ExpandedOccurrence]
    public var warnings: [CalendarWarning]
    public var eventCount: Int

    /// True when any warning makes availability uncertain (CAL-01 conservative planning).
    public var availabilityUncertain: Bool {
        warnings.contains { $0.makesAvailabilityUncertain }
    }
}

/// Options for one expansion.
public struct CalendarExpansionOptions: Sendable {
    /// Occurrences overlapping this window are returned.
    public var window: TimeRange
    /// The explicitly configured interpretation of floating times (CAL-01).
    public var floatingZone: TimeZone
    public var limits: ICalendarLimits

    public init(window: TimeRange, floatingZone: TimeZone, limits: ICalendarLimits = ICalendarLimits()) {
        self.window = window
        self.floatingZone = floatingZone
        self.limits = limits
    }
}
