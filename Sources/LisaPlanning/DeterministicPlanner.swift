// The documented deterministic planning algorithm (PLAN-03): identical inputs always produce identical plans.

import Foundation
import LisaDomain
import LisaTime

/// Places tasks and ideas into free time without ever violating a hard constraint (PLAN-02).
///
/// Algorithm:
/// 1. Available time is the planning windows minus busy events (widened by the buffer), protected time and blocks the
///    owner locked or completed. For today, time before `now` is not available.
/// 2. Items are ordered: confirmed deadline-sensitive tasks by deadline, then priority; other confirmed tasks by
///    priority; then eligible ideas by priority within the exploration budget. Ties break by creation time and then
///    by subject key, so ordering is stable.
/// 3. Each item goes to the earliest free interval long enough to hold it and, for deadlines, ending by the deadline.
///    Items are split only when marked splittable.
/// 4. Placement stops before total allocation exceeds `maximumAllocation` of the free time.
/// 5. Anything that does not fit is reported as unscheduled with its reason.
public enum DeterministicPlanner {
    public static func plan(_ input: PlanningInput) -> PlanningOutput {
        let zone = input.zone.timeZone
        let day = ZoneRules.dayRange(input.date, in: zone)
        let buffer = TimeInterval(max(0, input.settings.bufferMinutes) * 60)
        let windows = IntervalSet(input.settings.windows.compactMap { $0.range(on: input.date, in: zone) })
        var busy = IntervalSet(
            input.calendar.filter(\.blocksTime).map {
                TimeRange(
                    uncheckedStart: $0.range.start.addingTimeInterval(-buffer),
                    end: $0.range.end.addingTimeInterval(buffer))
            })
        let protected = IntervalSet(input.settings.protectedTime.compactMap { $0.range(on: input.date, in: zone) })
        var blocks: [PlanBlock] = []
        var unscheduled: [UnscheduledItem] = []
        var warnings: [String] = []
        var placedSubjects = Set<String>()

        for event in input.calendar where event.range.overlaps(day) {
            blocks.append(
                PlanBlock(
                    blockID: "event:\(event.occurrenceID.rawValue)", kind: .fixedEvent,
                    subject: .occurrence(event.occurrenceID),
                    title: event.title, range: event.range, state: .locked, provisional: false,
                    explanation: event.blocksTime ? "Calendar commitment" : "Calendar entry marked free"))
        }

        // Owner-locked and completed blocks are preserved exactly; accepted ones are kept unless they now conflict.
        // A preserved block holds its item: a splittable item's remaining time is planned as further parts below.
        var preserved = IntervalSet()
        var heldSeconds: [String: TimeInterval] = [:]
        var usedBlockIDs = Set<String>()
        for block in input.previousBlocks where block.kind != .fixedEvent {
            let keep: Bool
            switch block.state {
            case .locked, .completed: keep = true
            case .accepted: keep = !busy.overlaps(block.range) && !protected.overlaps(block.range)
            case .proposed, .rejected, .deferred: keep = false
            }
            guard keep else {
                if block.state == .accepted {
                    warnings.append(
                        "\"\(block.title)\" was accepted but now conflicts with the calendar; it was placed again")
                }
                continue
            }
            // A locked block stays where the owner put it, even when a calendar commitment now overlaps it (PLAN-04).
            if block.state == .locked,
                let event = input.calendar.first(where: { $0.blocksTime && $0.range.overlaps(block.range) })
            {
                warnings.append(
                    "\"\(block.title)\" is locked at a time that now overlaps \"\(event.title)\" on the calendar")
            }
            blocks.append(block)
            preserved.insert(block.range)
            heldSeconds[block.subject.key, default: 0] += block.range.duration
            usedBlockIDs.insert(block.blockID)
        }

        var free = windows.subtracting(busy).subtracting(protected).subtracting(preserved)
        if input.now > day.start {
            free = free.subtracting(
                IntervalSet([TimeRange(uncheckedStart: day.start, end: roundUp(input.now, minutes: 5))]))
        }
        let capacity = free.totalDuration * min(1, max(0, input.settings.maximumAllocation))
        var allocated: TimeInterval = 0
        var explorationUsed = 0
        let rejected = Set(input.rejected.map { "\($0.subjectKey)#\($0.inputFingerprint)" })

        for item in ordered(tasks: input.tasks, ideas: input.ideas, zone: zone) {
            guard !placedSubjects.contains(item.subject.key) else { continue }
            let seconds = TimeInterval(max(5, item.minutes) * 60)
            let held = heldSeconds[item.subject.key] ?? 0
            // An item the owner holds in the plan is placed; only a splittable one gets more parts for the time left.
            if held > 0, !item.splittable || held >= seconds { continue }
            let needed = seconds - held
            let neededMinutes = Int((needed / 60).rounded(.up))
            if rejected.contains("\(item.subject.key)#\(item.fingerprint(on: input.date))") {
                unscheduled.append(
                    UnscheduledItem(
                        subject: item.subject, title: item.title,
                        reason: "You rejected this suggestion; it returns when something relevant changes"))
                continue
            }
            if item.kind == .idea, explorationUsed + neededMinutes > input.settings.ideaExplorationBudgetMinutes {
                unscheduled.append(
                    UnscheduledItem(
                        subject: item.subject, title: item.title,
                        reason:
                            "The \(input.settings.ideaExplorationBudgetMinutes)-minute exploration budget for the day is used"
                    ))
                continue
            }
            let latest = item.deadline.map { $0.latestInstant(in: zone) }
            if let latest, latest <= max(input.now, day.start) {
                unscheduled.append(
                    UnscheduledItem(subject: item.subject, title: item.title, reason: "The deadline has passed"))
                continue
            }
            let ranges = place(seconds: needed, splittable: item.splittable, in: free, latestEnd: latest)
            guard !ranges.isEmpty else {
                let reason: String
                switch (latest == nil, held > 0) {
                case (true, false):
                    reason = "No free interval of \(item.minutes) minutes is left in today's planning windows"
                case (false, false): reason = "No free interval of \(item.minutes) minutes is left before the deadline"
                case (true, true):
                    reason =
                        "No free time is left in today's planning windows for the remaining \(neededMinutes) minutes"
                case (false, true):
                    reason = "No free time is left before the deadline for the remaining \(neededMinutes) minutes"
                }
                unscheduled.append(UnscheduledItem(subject: item.subject, title: item.title, reason: reason))
                continue
            }
            guard allocated + needed <= capacity + 0.5 else {
                unscheduled.append(
                    UnscheduledItem(
                        subject: item.subject, title: item.title,
                        reason:
                            "Planning more would exceed \(Int(input.settings.maximumAllocation * 100))% of the free time"
                    ))
                continue
            }
            var reasonText = explanation(for: item, ranges: ranges, zone: zone, uncertain: input.availabilityUncertain)
            if held > 0 {
                reasonText += "; the remaining \(neededMinutes) minutes, around the part already in the plan"
            }
            var nextIndex = 0
            for range in ranges {
                while usedBlockIDs.contains("\(item.subject.key)#\(nextIndex)") { nextIndex += 1 }
                let blockID = "\(item.subject.key)#\(nextIndex)"
                usedBlockIDs.insert(blockID)
                nextIndex += 1
                blocks.append(
                    PlanBlock(
                        blockID: blockID, kind: item.kind == .task ? .task : .idea,
                        subject: item.subject, title: item.title, range: range, state: .proposed,
                        provisional: input.availabilityUncertain,
                        explanation: reasonText))
                free = free.subtracting(IntervalSet([range]))
                busy.insert(range)
            }
            allocated += needed
            if item.kind == .idea { explorationUsed += neededMinutes }
            placedSubjects.insert(item.subject.key)
        }
        if input.availabilityUncertain {
            warnings.append("Some calendar data is stale or incomplete; proposed times are provisional")
        }
        blocks.sort { ($0.range.start, $0.blockID) < ($1.range.start, $1.blockID) }
        return PlanningOutput(blocks: blocks, unscheduled: unscheduled, warnings: warnings)
    }

    /// The baseline ordering (PLAN-03).
    static func ordered(tasks: [PlanningItem], ideas: [PlanningItem], zone: TimeZone) -> [PlanningItem] {
        let deadlineTasks = tasks.filter { $0.deadline != nil }.sorted { lhs, rhs in
            let left = lhs.deadline!.latestInstant(in: zone)
            let right = rhs.deadline!.latestInstant(in: zone)
            if left != right { return left < right }
            return tieBreak(lhs, rhs)
        }
        let otherTasks = tasks.filter { $0.deadline == nil }.sorted(by: tieBreak)
        return deadlineTasks + otherTasks + ideas.sorted(by: tieBreak)
    }

    private static func tieBreak(_ lhs: PlanningItem, _ rhs: PlanningItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.subject.key < rhs.subject.key
    }

    /// The earliest placement: one interval, or for splittable items several of at least 15 minutes.
    static func place(seconds: TimeInterval, splittable: Bool, in free: IntervalSet, latestEnd: Date?) -> [TimeRange] {
        for gap in free.ranges {
            let end = latestEnd.map { min(gap.end, $0) } ?? gap.end
            if end.timeIntervalSince(gap.start) >= seconds {
                return [TimeRange(start: gap.start, duration: seconds)]
            }
        }
        guard splittable else { return [] }
        var remaining = seconds
        var pieces: [TimeRange] = []
        for gap in free.ranges {
            let end = latestEnd.map { min(gap.end, $0) } ?? gap.end
            let length = end.timeIntervalSince(gap.start)
            guard length >= 15 * 60 else { continue }
            let piece = min(length, remaining)
            pieces.append(TimeRange(start: gap.start, duration: piece))
            remaining -= piece
            if remaining <= 0 { return pieces }
        }
        return []
    }

    private static func explanation(for item: PlanningItem, ranges: [TimeRange], zone: TimeZone, uncertain: Bool)
        -> String
    {
        var text: String
        switch item.kind {
        case .task where item.deadline != nil:
            text = "Earliest free time that finishes before the deadline"
        case .task:
            text = "Earliest free time for a \(item.priority.rawValue)-priority task"
        case .idea:
            text = "Time to explore this idea, within the daily exploration budget"
        }
        if ranges.count > 1 { text += "; split into \(ranges.count) parts because it is marked splittable" }
        if uncertain { text += " (provisional: calendar availability is uncertain)" }
        return text
    }

    private static func roundUp(_ instant: Date, minutes: Int) -> Date {
        let step = Int64(minutes * 60_000)
        let value = instant.millisecondsSince1970
        return Date(millisecondsSince1970: ((value + step - 1) / step) * step)
    }
}
