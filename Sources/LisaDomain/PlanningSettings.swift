// Planning windows, protected time, buffers, allocation limits and idea-exploration budget.

import Foundation
import LisaTime

/// A recurring local-time window on selected weekdays.
public struct LocalWindow: Hashable, Codable, Sendable {
    public var start: LocalTime
    public var end: LocalTime
    public var weekdays: Set<Weekday>
    public var label: String?

    public init(start: LocalTime, end: LocalTime, weekdays: Set<Weekday> = Set(Weekday.allCases), label: String? = nil)
    {
        self.start = start
        self.end = end
        self.weekdays = weekdays
        self.label = label
    }

    /// The instants covered on `date` in `zone`, or `nil` when the window does not apply that day.
    public func range(on date: LocalDate, in zone: TimeZone) -> TimeRange? {
        guard weekdays.contains(date.weekday), end > start else { return nil }
        let lower = ZoneRules.instant(for: LocalDateTime(date: date, time: start), in: zone)
        let upper = ZoneRules.instant(for: LocalDateTime(date: date, time: end), in: zone)
        return TimeRange(start: lower, end: upper)
    }
}

/// Settings for the deterministic planner (PLAN-02, PLAN-03).
public struct PlanningSettings: Hashable, Codable, Sendable {
    public var windows: [LocalWindow]
    public var protectedTime: [LocalWindow]
    /// Explicit buffer kept around busy events; travel time is never invented.
    public var bufferMinutes: Int
    /// The largest share of available time the planner may fill.
    public var maximumAllocation: Double
    public var ideaExplorationBudgetMinutes: Int
    public var defaultTaskMinutes: Int
    public var defaultIdeaMinutes: Int

    public init(
        windows: [LocalWindow], protectedTime: [LocalWindow] = [], bufferMinutes: Int = 0,
        maximumAllocation: Double = 0.75, ideaExplorationBudgetMinutes: Int = 60, defaultTaskMinutes: Int = 30,
        defaultIdeaMinutes: Int = 30
    ) {
        self.windows = windows
        self.protectedTime = protectedTime
        self.bufferMinutes = bufferMinutes
        self.maximumAllocation = maximumAllocation
        self.ideaExplorationBudgetMinutes = ideaExplorationBudgetMinutes
        self.defaultTaskMinutes = defaultTaskMinutes
        self.defaultIdeaMinutes = defaultIdeaMinutes
    }

    /// Weekdays 09:00–17:00 with no protected time.
    public static let defaultValue = PlanningSettings(
        windows: [
            LocalWindow(
                start: LocalTime(secondsSinceMidnight: 9 * 3600), end: LocalTime(secondsSinceMidnight: 17 * 3600),
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday])
        ])
}
