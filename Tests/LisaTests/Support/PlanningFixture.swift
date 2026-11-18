// Test-only. The R1 §16.2 concrete planning fixture exactly as the specification states it, and builders for planner
// inputs and plan blocks (L11, §16.3; later replanning tests, L12).

import Foundation
import LisaDomain
import LisaPlanning
import LisaTime

/// The §16.2 fixture: 2026-11-16 in America/New_York, planning window 09:00–12:00, zero buffer, a busy event
/// 10:00–11:00, a confirmed 30-minute task due at 10:00 with a higher priority than an eligible 30-minute idea, and no
/// other constraints.
enum PlanningFixture {
    static let date = TestTime.date("2026-11-16")
    static let zone = TestTime.newYork
    /// 07:00 on the fixture's day: before the window opens, so the whole window is still ahead.
    static let now = TestTime.instant("2026-11-16T07:00", in: TestTime.newYork)
    /// When the fixture's items were created.
    static let createdAt = TestTime.instant("2026-11-13T12:00", in: TestTime.newYork)

    /// The window 09:00–12:00 on every day, a zero buffer and no protected time; every other setting keeps its
    /// documented default (D-15).
    static let settings = PlanningSettings(
        windows: [LocalWindow(start: TestTime.time("09:00"), end: TestTime.time("12:00"))], bufferMinutes: 0)

    /// The busy calendar event, 10:00–11:00.
    static let busyEvent = busy("fixture-event-1000", "10:00", "11:00", title: "Fixture busy event")
    /// The busy event added afterwards, 09:00–09:30.
    static let addedEvent = busy("fixture-event-0900", "09:00", "09:30", title: "Fixture added event")

    /// The confirmed task: 30 minutes, deadline 10:00, a higher priority than the idea.
    static let task = item(
        .task, id: "fixture-task", title: "Fixture task", minutes: 30, priority: .high,
        deadline: .at(instant: TestTime.instant("2026-11-16T10:00", in: TestTime.newYork), zone: TestTime.newYork))
    /// The eligible idea: 30 minutes.
    static let idea = item(.idea, id: "fixture-idea", title: "Fixture idea", minutes: 30, priority: .normal)

    /// A calendar block from local `start` to `end` (`HH:MM`) on `date` (by default the fixture's day).
    static func busy(
        _ id: String, _ start: String, _ end: String, title: String = "Busy", blocksTime: Bool = true,
        on date: LocalDate = PlanningFixture.date, in zone: TimeZoneID = PlanningFixture.zone
    ) -> CalendarBlock {
        CalendarBlock(
            occurrenceID: OccurrenceID(id), title: title, range: TestTime.range(start, end, on: date.iso, in: zone),
            blocksTime: blocksTime)
    }

    /// A task or idea for the planner. Identifiers are fixed, so ordering and block IDs are reproducible.
    static func item(
        _ kind: PlanningItem.Kind, id: String, title: String? = nil, minutes: Int, priority: TaskPriority = .normal,
        deadline: Deadline? = nil, splittable: Bool = false, createdAt: Date = PlanningFixture.createdAt
    ) -> PlanningItem {
        let subject: PlanSubject = kind == .task ? .task(TaskID(id)) : .idea(IdeaID(id))
        return PlanningItem(
            kind: kind, subject: subject, title: title ?? id, minutes: minutes, priority: priority, deadline: deadline,
            splittable: splittable, createdAt: createdAt)
    }

    /// A block from an earlier plan revision for `item`, from local `start` to `end` on the fixture's day.
    static func block(
        _ blockID: String, for item: PlanningItem, _ start: String, _ end: String, state: PlanBlockState
    ) -> PlanBlock {
        PlanBlock(
            blockID: blockID, kind: item.kind == .task ? .task : .idea, subject: item.subject, title: item.title,
            range: TestTime.range(start, end, on: date.iso, in: zone), state: state, provisional: false,
            explanation: "an earlier revision")
    }

    /// A planner input for `date` in `zone` at `now`; by default the fixture's day, task and idea.
    static func input(
        calendar: [CalendarBlock], tasks: [PlanningItem] = [PlanningFixture.task],
        ideas: [PlanningItem] = [PlanningFixture.idea], settings: PlanningSettings = PlanningFixture.settings,
        previousBlocks: [PlanBlock] = [], rejected: [RejectedSuggestion] = [], availabilityUncertain: Bool = false,
        date: LocalDate = PlanningFixture.date, zone: TimeZoneID = PlanningFixture.zone,
        now: Date = PlanningFixture.now
    ) -> PlanningInput {
        PlanningInput(
            date: date, zone: zone, settings: settings, now: now, calendar: calendar, tasks: tasks, ideas: ideas,
            previousBlocks: previousBlocks, rejected: rejected, availabilityUncertain: availabilityUncertain)
    }
}
