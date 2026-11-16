// The `planning` section: planning windows, protected time, buffers, allocation and duration defaults.

import LisaDomain
import LisaTime

/// Decodes `planning` into the planner's settings (PLAN-02, PLAN-03, MEM-01). Absent settings keep the R1 defaults
/// of `PlanningSettings.defaultValue`: weekdays 09:00–17:00, no protected time, no buffer, at most 75% of free time
/// allocated, a 60-minute daily idea budget, and 30-minute task and idea durations.
enum PlanningSection {
    static func decode(_ section: ConfigSection?) -> PlanningSettings {
        let defaults = PlanningSettings.defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return PlanningSettings(
            windows: windows(section, "windows") ?? defaults.windows,
            protectedTime: windows(section, "protectedTime") ?? defaults.protectedTime,
            bufferMinutes: section.integer("bufferMinutes", default: defaults.bufferMinutes, in: 0...240),
            maximumAllocation: section.number("maximumAllocation", default: defaults.maximumAllocation, in: 0.05...1),
            ideaExplorationBudgetMinutes: section.integer(
                "ideaExplorationBudgetMinutes", default: defaults.ideaExplorationBudgetMinutes, in: 0...480),
            defaultTaskMinutes: section.integer(
                "defaultTaskMinutes", default: defaults.defaultTaskMinutes, in: 5...480),
            defaultIdeaMinutes: section.integer("defaultIdeaMinutes", default: defaults.defaultIdeaMinutes, in: 5...480)
        )
    }

    private static func windows(_ section: ConfigSection, _ key: String) -> [LocalWindow]? {
        guard let entries = section.list(key, maxCount: 50) else { return nil }
        let windows = entries.map(window)
        return windows.allSatisfy { $0 != nil } ? windows.compactMap { $0 } : nil
    }

    /// `{ days: "weekdays", start: "09:00", end: "17:00", label: "Focus" }`; the label is optional.
    private static func window(_ value: ConfigValue) -> LocalWindow? {
        guard let entry = value.section() else { return nil }
        defer { entry.finish() }
        let days: Set<Weekday>?
        if let daysValue = entry.value("days") {
            days = weekdays(daysValue)
        } else {
            entry.reportMissing(
                "days", fix: "write \"daily\", \"weekdays\", \"weekend\" or a list such as [\"mon\", \"wed\"]")
            days = nil
        }
        let start = entry.requiredTime("start", fix: "write a time such as \"09:00\"")
        let end = entry.requiredTime("end", fix: "write a time such as \"17:00\"")
        let label = entry.text("label", maxLength: 100)
        guard let days, let start, let end else { return nil }
        guard start < end else {
            entry.report(
                "end", "must be later than start; a window cannot cross midnight",
                fix: "split it into two windows, one ending at 23:59 and one starting at 00:00")
            return nil
        }
        return LocalWindow(start: start, end: end, weekdays: days, label: label)
    }

    /// `"daily"`, `"weekdays"`, `"weekend"`, or a list of day names such as `["mon", "wed"]` (any case).
    private static func weekdays(_ value: ConfigValue) -> Set<Weekday>? {
        let expected = "must be \"daily\", \"weekdays\", \"weekend\" or a list of days such as [\"mon\", \"wed\"]"
        switch value.node.value {
        case .string(let text):
            switch text {
            case "daily": return Set(Weekday.allCases)
            case "weekdays": return [.monday, .tuesday, .wednesday, .thursday, .friday]
            case "weekend": return [.saturday, .sunday]
            default:
                value.report(expected)
                return nil
            }
        case .array:
            guard let elements = value.elements(maxCount: 7) else { return nil }
            guard !elements.isEmpty else {
                value.report("must name at least one day")
                return nil
            }
            var days: Set<Weekday> = []
            var valid = true
            for element in elements {
                guard let name = element.text(maxLength: 16) else {
                    valid = false
                    continue
                }
                guard let day = Weekday.allCases.first(where: { $0.englishNames.contains(name.lowercased()) }) else {
                    element.report("must be a day such as mon, tue, wed, thu, fri, sat or sun")
                    valid = false
                    continue
                }
                if !days.insert(day).inserted {
                    element.report("repeats a day that is already listed")
                    valid = false
                }
            }
            return valid ? days : nil
        default:
            value.report(expected + ", not \(value.typeDescription)")
            return nil
        }
    }
}
