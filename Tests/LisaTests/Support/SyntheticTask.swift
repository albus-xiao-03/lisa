// Test-only. Builds LisaTask records with synthetic titles, for the policy and time suites (L17, L31, L33, §16.3) and
// later reminder and delivery tests (L15, L16).

import Foundation
import LisaDomain
import LisaTime

/// Synthetic tasks. Titles are made up; nothing refers to a real person or commitment.
enum SyntheticTask {
    /// A confirmed, open task (a commitment the owner confirmed).
    static func confirmed(
        _ title: String = "Submit the synthetic filing", priority: TaskPriority = .high, deadline: Deadline?,
        createdAt: Date, id: TaskID = .random()
    ) -> LisaTask {
        LisaTask(
            id: id, title: title, priority: priority, deadline: deadline, confirmation: .confirmed, origin: .manual,
            now: createdAt)
    }

    /// An open task whose confirmation is only `confirmation` (for example model output that is not the owner's own
    /// words), created from extraction.
    static func unconfirmed(
        _ title: String = "Possibly submit the synthetic filing", confirmation: Confirmation = .possible,
        priority: TaskPriority = .high, deadline: Deadline?, createdAt: Date, id: TaskID = .random()
    ) -> LisaTask {
        LisaTask(
            id: id, title: title, priority: priority, deadline: deadline, confirmation: confirmation,
            origin: .extracted, now: createdAt)
    }

    /// A timed deadline at `instant`, keeping `zone` as the source zone.
    static func due(_ instant: Date, zone: TimeZoneID = TestTime.newYork) -> Deadline {
        .at(instant: instant, zone: zone)
    }

    /// `task` after its lifecycle moved it to `status` at `now` (for example open → completed).
    static func moved(_ task: LisaTask, to status: TaskStatus, at now: Date) throws -> LisaTask {
        var copy = task
        try copy.transition(to: status, at: now)
        return copy
    }
}
