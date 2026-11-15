// Daily plans (PLAN-01–PLAN-05): deterministic computation, explained revisions, block actions and rejections.

import Foundation
import LisaDomain
import LisaLogging
import LisaPlanning
import LisaPorts
import LisaTime

/// An owner action on a plan block.
public enum PlanBlockAction: String, Codable, Sendable, CaseIterable {
    case accept
    case lock
    case reject
    case complete
    case `defer`
}

/// Computes and stores plans. Accepted and locked blocks are preserved; rejected suggestions stay rejected until
/// the underlying item changes.
public final class PlanService: Sendable {
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let settings: any SettingsSource

    public init(store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
    }

    /// Computes the plan for `date` and stores it as a new revision when anything changed.
    @discardableResult
    public func compute(for date: LocalDate) throws -> Plan {
        let owner = try settings.currentSettings()
        let zone = owner.zone.timeZone
        let now = clock.now()
        return try store.write { tx in
            let previous = try tx.first(
                Plan.self, RecordQuery.all.filter("natural_key", equals: Plan.key(date: date, zone: owner.zone)))
            let (calendar, basis) = try Self.calendar(on: date, zone: zone, now: now, in: tx)
            let tasks = try Self.taskItems(owner: owner, in: tx)
            let ideas = try Self.ideaItems(owner: owner, in: tx)
            let output = DeterministicPlanner.plan(
                PlanningInput(
                    date: date, zone: owner.zone, settings: owner.planning, now: now, calendar: calendar, tasks: tasks,
                    ideas: ideas, previousBlocks: previous?.blocks ?? [], rejected: previous?.rejectedSuggestions ?? [],
                    availabilityUncertain: basis.availabilityUncertain))
            try Self.recordUnschedulable(output.unscheduled, previous: previous, now: now, in: tx)
            if var plan = previous {
                guard
                    plan.blocks != output.blocks || plan.unscheduled != output.unscheduled
                        || plan.warnings != output.warnings
                        || plan.basis.availabilityUncertain != basis.availabilityUncertain
                else { return plan }
                plan.changes = PlanDiff.explain(previous: plan.blocks, current: output.blocks, zone: zone)
                plan.blocks = output.blocks
                plan.unscheduled = output.unscheduled
                plan.warnings = output.warnings
                plan.basis = basis
                plan.updatedAt = now
                return try tx.update(plan)
            }
            return try tx.insert(
                Plan(
                    localDate: date, zone: owner.zone, blocks: output.blocks, unscheduled: output.unscheduled,
                    basis: basis, warnings: output.warnings, now: now))
        }
    }

    /// Fixed events for the day and the freshness of the calendars they come from.
    static func calendar(on date: LocalDate, zone: TimeZone, now: Date, in tx: any RecordReading) throws
        -> ([CalendarBlock], PlanBasis)
    {
        let day = ZoneRules.dayRange(date, in: zone)
        let occurrences = try tx.find(
            CalendarOccurrence.self,
            RecordQuery.all.filter("start_at", .lessThan, .instant(day.end)).filter(
                "end_at", .greaterThan, .instant(day.start)))
        let blocks = occurrences.filter { $0.status != .cancelled }.map { occurrence in
            CalendarBlock(
                occurrenceID: occurrence.id, title: occurrence.title, range: occurrence.range(in: zone),
                blocksTime: occurrence.blocksTime)
        }
        let sources = try tx.find(Source.self, RecordQuery.all.filter("kind", equals: SourceKind.calendarFeed.rawValue))
        var freshness: [String: SourceFreshness] = [:]
        var refreshed: [String: Date] = [:]
        for source in sources where source.enabled {
            freshness[source.id.rawValue] = source.freshness(at: now)
            refreshed[source.id.rawValue] = source.lastSuccessAt
        }
        let uncertain =
            freshness.values.contains { $0 != .fresh } || sources.contains { $0.enabled && $0.isFailing }
            || occurrences.contains { !$0.warnings.isEmpty }
        return (
            blocks,
            PlanBasis(
                sourceFreshness: freshness, sourceRefreshedAt: refreshed, availabilityUncertain: uncertain,
                computedAt: now)
        )
    }

    /// Open confirmed tasks; possible tasks and unconfirmed deadlines never constrain the plan (PLAN-05).
    static func taskItems(owner: OwnerSettings, in tx: any RecordReading) throws -> [PlanningItem] {
        try tx.find(
            LisaTask.self,
            RecordQuery.all.filter("status", in: [TaskStatus.open, .inProgress].map { .text($0.rawValue) })
        ).filter(\.isConfirmedCommitment).map { item(for: $0, owner: owner) }
    }

    static func item(for task: LisaTask, owner: OwnerSettings) -> PlanningItem {
        PlanningItem(
            kind: .task, subject: .task(task.id), title: task.title,
            minutes: task.estimatedMinutes ?? owner.planning.defaultTaskMinutes, priority: task.priority,
            deadline: task.deadline, splittable: task.splittable, createdAt: task.createdAt)
    }

    static func ideaItems(owner: OwnerSettings, in tx: any RecordReading) throws -> [PlanningItem] {
        try tx.find(
            Idea.self,
            RecordQuery.all.filter(
                "lifecycle", in: [IdeaLifecycle.availableForPlanning, .scheduled].map { .text($0.rawValue) })
        ).map { item(for: $0, owner: owner) }
    }

    static func item(for idea: Idea, owner: OwnerSettings) -> PlanningItem {
        PlanningItem(
            kind: .idea, subject: .idea(idea.id), title: idea.summary,
            minutes: idea.estimatedMinutes ?? owner.planning.defaultIdeaMinutes, priority: idea.priority,
            deadline: idea.deadline, splittable: false, createdAt: idea.createdAt)
    }

    /// Keeps ideas that cannot be scheduled visible with the reason (IDEA-01), counting each new occurrence once.
    static func recordUnschedulable(
        _ unscheduled: [UnscheduledItem], previous: Plan?, now: Date, in tx: any RecordWriting
    )
        throws
    {
        let before = Set((previous?.unscheduled ?? []).map { "\($0.subject.key)|\($0.reason)" })
        for item in unscheduled {
            guard case .idea(let id) = item.subject, !before.contains("\(item.subject.key)|\(item.reason)"),
                var idea = try tx.get(Idea.self, id: id)
            else { continue }
            idea.unschedulableReason = item.reason
            idea.unschedulableCount += 1
            idea.updatedAt = now
            try tx.update(idea)
        }
    }

    /// Applies an owner action to a block. Rejecting remembers the suggestion's fingerprint; completing an idea
    /// block marks the idea explored, while merely scheduling it never does.
    public func act(
        _ action: PlanBlockAction, planID: PlanID, blockID: String, expectedRevision: Revision, by principal: Principal
    ) throws -> Plan {
        switch principal {
        case .localOwner, .pairedDevice, .demonstration: break
        case .runtime, .model: throw DomainError.notPermitted("plan blocks are changed only by the owner")
        }
        let owner = try settings.currentSettings()
        let now = clock.now()
        return try store.write { tx in
            var plan = try tx.require(Plan.self, id: planID)
            guard plan.revision == expectedRevision else {
                throw StoreError.conflict(
                    collection: Plan.collectionName, id: planID.rawValue, expected: expectedRevision,
                    actual: plan.revision)
            }
            guard let index = plan.blocks.firstIndex(where: { $0.blockID == blockID }) else {
                throw StoreError.notFound(collection: "plan blocks", id: blockID)
            }
            let block = plan.blocks[index]
            guard block.kind != .fixedEvent else {
                throw DomainError.notPermitted("calendar events are changed in the calendar, not in the plan")
            }
            switch action {
            case .accept:
                plan.blocks[index].state = .accepted
                if case .idea(let id) = block.subject, var idea = try tx.get(Idea.self, id: id),
                    idea.lifecycle == .availableForPlanning
                {
                    try idea.transition(to: .scheduled, at: now)
                    try tx.update(idea)
                }
            case .lock:
                plan.blocks[index].state = .locked
            case .reject:
                plan.blocks[index].state = .rejected
                if let fingerprint = try Self.fingerprint(block.subject, date: plan.localDate, owner: owner, in: tx) {
                    plan.rejectedSuggestions.append(
                        RejectedSuggestion(subjectKey: block.subject.key, inputFingerprint: fingerprint))
                }
            case .complete:
                plan.blocks[index].state = .completed
                if case .idea(let id) = block.subject, var idea = try tx.get(Idea.self, id: id),
                    idea.lifecycle == .scheduled || idea.lifecycle == .availableForPlanning
                {
                    try idea.transition(to: .explored, at: now)
                    try tx.update(idea)
                }
            case .defer:
                plan.blocks[index].state = .deferred
            }
            plan.updatedAt = now
            let saved = try tx.update(plan)
            try tx.insert(
                AuditEvent(
                    action: "plan.block-\(action.rawValue)", actor: principal, at: now,
                    affected: [planID.rawValue, blockID], outcome: .succeeded, detail: block.kind.rawValue))
            return saved
        }
    }

    static func fingerprint(_ subject: PlanSubject, date: LocalDate, owner: OwnerSettings, in tx: any RecordReading)
        throws
        -> String?
    {
        switch subject {
        case .task(let id): try tx.get(LisaTask.self, id: id).map { item(for: $0, owner: owner).fingerprint(on: date) }
        case .idea(let id): try tx.get(Idea.self, id: id).map { item(for: $0, owner: owner).fingerprint(on: date) }
        case .occurrence: nil
        }
    }
}
