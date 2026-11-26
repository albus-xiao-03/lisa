// The projection of a task's merge state into R1's `tasks` record (plan §8.4.1 step 5, §8.3.4), which R1's API, its
// planner and its reminders read. Candidates resolve as the planner treats them: the earliest deadline, the longest
// estimate, the highest priority, splittable only when every candidate is; the title and the confirmation follow the
// register's display order; notes are the live pieces in order, separated by a blank line. An existing record changes
// field by field under R1's own rules (TaskService, LisaTask.transition): a material change (priority, deadline,
// confirmation) or a status change advances `changeSequence`, an owner change to a correctable field marks it
// owner-corrected, and completion sets `completedAt`. "Completed and cancelled" shows as cancelled, R1 having no such
// status. A deleted task's record is removed; its tombstone stays in the ledger.

import Foundation
import LisaDomain
import LisaMerge
import LisaPorts
import LisaSQLite
import LisaSyncProtocol
import LisaTime

enum TaskProjection {
    /// Writes `view` into R1's record of `entityID` and returns the revision written, if any; `createdAt` is the
    /// creation's display time. With `force`, an
    /// existing record is written even when no field changed, as R1's `TaskService.correct` does, so one R1 service
    /// call is one revision step (§8.12.2 "Projection revisions"). With `markDeadlineCorrected`, the deadline is
    /// marked owner-corrected even when its value didn't change, as `TaskService.correct` marks it whenever a
    /// correction sets or clears it (D-72).
    static func project(
        _ view: TaskView?, entityID: Identifier128, createdAt: Date?, commitTime: Date, into records: any RecordWriting,
        force: Bool = false, markDeadlineCorrected: Bool = false
    ) throws -> Int64? {
        let id = TaskID(R1Identity.uuidString(entityID))
        let existing = try records.get(LisaTask.self, id: id)
        guard let view, view.exists, !view.isDeleted else {
            if existing != nil { try records.delete(LisaTask.self, id: id) }
            return nil
        }
        let title = view.title.first ?? ""
        let notes = view.notes.joined(separator: "\n\n")
        let priority = view.priority.compactMap(TaskPriority.init(rawValue:)).max() ?? .normal
        let deadline = earliest(view.deadline)
        let estimate = view.estimate.compactMap { $0 }.max().map { Int(clamping: $0) }
        let splittable = !view.splittable.isEmpty && view.splittable.allSatisfy { $0 }
        let confirmation = view.confirmation.first.flatMap(Confirmation.init(rawValue:)) ?? .confirmed
        guard var task = existing else {
            var task = LisaTask(
                id: id, title: title, notes: notes, priority: priority, deadline: deadline, estimatedMinutes: estimate,
                splittable: splittable, confirmation: confirmation, origin: .manual, now: createdAt ?? commitTime)
            task.status = status(view.status, current: .open)
            if task.status == .completed { task.completedAt = commitTime }
            task.updatedAt = commitTime
            return try records.insert(task).revision.value
        }
        var changed = false
        var material = false
        if title != task.title {
            task.title = title
            task.ownerCorrected.insert(.title)
            changed = true
        }
        if notes != task.notes {
            task.notes = notes
            changed = true
        }
        if priority != task.priority {
            task.priority = priority
            task.ownerCorrected.insert(.priority)
            material = true
        }
        if deadline != task.deadline {
            task.deadline = deadline
            task.unresolvedDeadlineText = nil
            task.ownerCorrected.insert(.deadline)
            material = true
        }
        if estimate != task.estimatedMinutes {
            task.estimatedMinutes = estimate
            task.ownerCorrected.insert(.duration)
            changed = true
        }
        if splittable != task.splittable {
            task.splittable = splittable
            changed = true
        }
        if confirmation != task.confirmation {
            task.confirmation = confirmation
            task.ownerCorrected.insert(.confirmation)
            material = true
        }
        let status = status(view.status, current: task.status)
        if status != task.status {
            task.status = status
            task.completedAt = status == .completed ? commitTime : nil
            if task.origin == .extracted { task.ownerCorrected.insert(.status) }
            material = true
        }
        if markDeadlineCorrected { task.ownerCorrected.insert(.deadline) }
        guard changed || material || force else { return nil }
        if material { task.changeSequence += 1 }
        task.updatedAt = commitTime
        return try records.update(task).revision.value
    }

    /// Records that R1's revision `revision` of `entityID` reflects every commit up to `position` in the dataset's
    /// current epoch, so a v1 edit "observed at projection revision N" can be mapped to the pieces it saw (plan §8.3.2,
    /// §8.12.2).
    static func recordRevision(
        _ revision: Int64?, of entityID: Identifier128, at position: Int64, in session: SQLiteSession
    )
        throws
    {
        guard let revision else { return }
        try session.query(
            """
            INSERT OR REPLACE INTO core_projection_revisions (entity_id, revision, epoch_id, position)
            VALUES (?, ?, ?, ?)
            """,
            [
                CoreColumns.id(entityID), .integer(revision), CoreColumns.id(try CoreLedger.epoch(in: session)),
                .integer(position),
            ])
    }

    /// R1's status for a merge status: an open task keeps R1's own in-progress or blocked state.
    static func status(_ merged: TerminalActions.Status, current: TaskStatus) -> TaskStatus {
        switch merged {
        case .open: current.isActive ? current : .open
        case .completed: .completed
        case .cancelled, .completedAndCancelled: .cancelled
        }
    }

    /// The earliest deadline among the candidates, by its latest instant in UTC; `nil` when none sets one.
    static func earliest(_ candidates: [WireDeadline?]) -> Deadline? {
        let utc = TimeZone(identifier: "UTC") ?? .current
        return candidates.compactMap { $0.flatMap(deadline) }.min {
            $0.latestInstant(in: utc) < $1.latestInstant(in: utc)
        }
    }

    static func deadline(_ wire: WireDeadline) -> Deadline? {
        switch wire {
        case .instant(let milliseconds, let zone):
            .at(instant: Date(timeIntervalSince1970: Double(milliseconds) / 1_000), zone: zone.flatMap(TimeZoneID.init))
        case .date(let text):
            LocalDate(iso: text).map(Deadline.onDate)
        }
    }
}
