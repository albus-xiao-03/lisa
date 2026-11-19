// Everything the deterministic planner needs for one local date, independent of storage.

import Foundation
import LisaDomain
import LisaTime

/// A calendar occurrence shown in the rundown. Only `blocksTime` occurrences constrain planning.
public struct CalendarBlock: Hashable, Sendable {
    public var occurrenceID: OccurrenceID
    public var title: String
    public var range: TimeRange
    public var blocksTime: Bool

    public init(occurrenceID: OccurrenceID, title: String, range: TimeRange, blocksTime: Bool) {
        self.occurrenceID = occurrenceID
        self.title = title
        self.range = range
        self.blocksTime = blocksTime
    }
}

/// A task or idea that may be placed.
public struct PlanningItem: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case task
        case idea
    }

    public var kind: Kind
    public var subject: PlanSubject
    public var title: String
    public var minutes: Int
    public var priority: TaskPriority
    /// Only confirmed deadlines are passed in; unconfirmed ones never constrain planning (PLAN-05).
    public var deadline: Deadline?
    public var splittable: Bool
    public var createdAt: Date

    public init(
        kind: Kind, subject: PlanSubject, title: String, minutes: Int, priority: TaskPriority, deadline: Deadline?,
        splittable: Bool, createdAt: Date
    ) {
        self.kind = kind
        self.subject = subject
        self.title = title
        self.minutes = minutes
        self.priority = priority
        self.deadline = deadline
        self.splittable = splittable
        self.createdAt = createdAt
    }

    /// Identifies the suggestion so that a rejection is remembered until something relevant changes.
    public func fingerprint(on date: LocalDate) -> String {
        "\(subject.key)|\(minutes)|\(String(describing: deadline))|\(priority.rawValue)|\(date.iso)"
    }
}

/// The planner's input.
public struct PlanningInput: Sendable {
    public var date: LocalDate
    public var zone: TimeZoneID
    public var settings: PlanningSettings
    public var now: Date
    public var calendar: [CalendarBlock]
    public var tasks: [PlanningItem]
    public var ideas: [PlanningItem]
    /// Blocks from the previous revision that the owner locked, accepted or completed.
    public var previousBlocks: [PlanBlock]
    public var rejected: [RejectedSuggestion]
    /// True when an enabled calendar is stale or incomplete; proposals are then provisional (CAL-02, PLAN-05).
    public var availabilityUncertain: Bool

    public init(
        date: LocalDate, zone: TimeZoneID, settings: PlanningSettings, now: Date, calendar: [CalendarBlock],
        tasks: [PlanningItem], ideas: [PlanningItem], previousBlocks: [PlanBlock] = [],
        rejected: [RejectedSuggestion] = [], availabilityUncertain: Bool = false
    ) {
        self.date = date
        self.zone = zone
        self.settings = settings
        self.now = now
        self.calendar = calendar
        self.tasks = tasks
        self.ideas = ideas
        self.previousBlocks = previousBlocks
        self.rejected = rejected
        self.availabilityUncertain = availabilityUncertain
    }
}

/// The planner's output.
public struct PlanningOutput: Hashable, Sendable {
    public var blocks: [PlanBlock]
    public var unscheduled: [UnscheduledItem]
    public var warnings: [String]
}
