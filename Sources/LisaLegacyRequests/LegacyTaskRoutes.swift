// R1's task routes as legacy conversions (plan §8.12.2, the route table; docs/DECISIONS.md D-71): R1's checks, then
// the request's Core-signed children taken in through the ledger and projected into R1's record once, with R1's own
// audit event, inside the conversion's transaction. The caller renders R1's answer, records it with the parent, and
// propagates R1's domain changes after the commit, as R1's application does after its service call.

import Foundation
import LisaCoreLedger
import LisaDomain
import LisaOwnerData
import LisaPorts
import LisaSyncProtocol
import LisaTime

/// R2's converter of R1 requests at Core: the ledger whose frame keeps the parents, and the dataset of its children.
public struct LegacyConverter: Sendable {
    public let ledger: CoreLedger

    public init(ledger: CoreLedger) {
        self.ledger = ledger
    }

    public var datasetID: Identifier128 { ledger.datasetID }
}

/// The parent's key: the caller's scope (`owner` or `device:<id>`) and R1's request ID, in the converter's dataset.
public struct LegacyRequestContext: Hashable, Sendable {
    public let datasetID: Identifier128
    public let scope: String
    public let requestID: String

    public init(datasetID: Identifier128, scope: String, requestID: String) {
        self.datasetID = datasetID
        self.scope = scope
        self.requestID = requestID
    }

    /// The task a `POST /v1/tasks` of this key creates, derived from the parent (plan §8.12.2).
    public var createdTaskID: TaskID {
        TaskID(
            R1Identity.uuidString(
                LegacyDerivation.createdEntityID(
                    dataset: datasetID, scope: scope, requestID: requestID, discriminator: LegacyTaskRoutes.create)))
    }
}

/// What a converted task route did: R1's record after it, every child with its disposition, the set digest, and the
/// domain changes R1's service would have returned.
public struct LegacyTaskEffect: Sendable {
    public let task: LisaTask
    public let children: [LegacyChildDisposition]
    public let setDigest: Digest256
    public let changes: [DomainChange]
}

public enum LegacyRouteError: Error, Hashable, Sendable {
    /// A child the ledger didn't decide as applied; the conversion is rolled back.
    case childNotApplied(index: Int, outcome: String)
    /// The projection wrote no record for the entity.
    case notProjected(TaskID)
    /// An R1 record whose ID isn't a UUID, so no R2 entity names it.
    case unmapped(TaskID)
}

public enum LegacyTaskRoutes {
    /// The discriminator of a created task's child.
    public static let create = "create:task"
    /// The discriminator of a task's notes child (D-71 for creation).
    public static let notes = "field:notes"

    /// `POST /v1/tasks`'s checks, in `TaskService.create`'s order and with its errors: the principal, then the title
    /// (trimmed, 1–200 characters), then the minutes (1–1440). Returns the draft with the trimmed title.
    public static func checkedCreation(_ draft: TaskDraft, by principal: Principal) throws -> TaskDraft {
        try TaskService.requireOwnerOrDevice(principal)
        var checked = draft
        checked.title = try TaskService.validTitle(draft.title)
        try TaskService.validateMinutes(draft.estimatedMinutes)
        return checked
    }

    /// `POST /v1/tasks` after its checks: the `create:task` child and, when the draft has notes, a `field:notes`
    /// child (`note.add`) chained to it (D-71). Both are taken in and projected once, so R1's record is created at
    /// revision 1, with R1's `task.created` audit event, as `TaskService.create` writes them.
    public static func create(
        _ draft: TaskDraft, by principal: Principal, context: LegacyRequestContext, in tx: LegacyTransaction
    ) throws -> LegacyTaskEffect {
        let entity = LegacyDerivation.createdEntityID(
            dataset: context.datasetID, scope: context.scope, requestID: context.requestID, discriminator: create)
        let creation = try TaskCreation(
            title: draft.title, priority: draft.priority.rawValue, deadline: draft.deadline.map(wire),
            estimate: draft.estimatedMinutes.map(Int64.init), splittable: draft.splittable,
            confirmation: Confirmation.confirmed.rawValue)
        var changes = [
            try change(create, entity, .taskCreate(creation))
        ]
        if !draft.notes.isEmpty { changes.append(try change(notes, entity, .noteAdd(text: draft.notes))) }
        let set = try LegacyChildSet(
            datasetID: context.datasetID, scope: context.scope, requestID: context.requestID, changes: changes)
        let children = try dispositions(
            try tx.intake(try set.signed(with: tx.signer), projecting: false), set: set, changes: changes)
        try tx.project(entity, forceRevision: false)
        let id = TaskID(R1Identity.uuidString(entity))
        guard let task = try tx.records.get(LisaTask.self, id: id) else { throw LegacyRouteError.notProjected(id) }
        try tx.records.insert(TaskService.audit("task.created", task, principal, tx.now))
        return LegacyTaskEffect(task: task, children: children, setDigest: set.setDigest, changes: [.taskCreated(id)])
    }

    /// The discriminator of a PATCH's status child.
    public static let status = "status"

    /// `PATCH /v1/tasks/{id}`'s correction checks, in `TaskService.correct`'s order and with its errors: the principal,
    /// the minutes, then the title. Returns the correction with the trimmed title.
    public static func checkedCorrection(_ correction: TaskCorrection, by principal: Principal) throws
        -> TaskCorrection
    {
        try TaskService.requireOwnerOrDevice(principal)
        try TaskService.validateMinutes(correction.estimatedMinutes)
        var checked = correction
        checked.title = try correction.title.map(TaskService.validTitle)
        return checked
    }

    /// What a converted PATCH did: R1's record after it, every child with its disposition, the set digest, R1's domain
    /// changes, and R1's refusal of the status when R1's rules refuse it, with the correction left committed.
    public struct UpdateEffect: Sendable {
        public let task: LisaTask
        public let children: [LegacyChildDisposition]
        public let setDigest: Digest256?
        public let changes: [DomainChange]
        public let statusRefusal: (any Error)?
    }

    /// `PATCH /v1/tasks/{id}` after the caller's checks, all inside the parent: the record exists, its revision is
    /// `expectedRevision` N, and the correction passed `checkedCorrection` when it changes anything (D-72).
    /// - **The field children:** one per field the correction carries, named after R1's field and observed at N, are
    ///   projected once as one R1 revision step, with R1's `task.corrected` audit event.
    /// - **The status child** depends on the target alone: `task.complete`, `task.cancel`, or `task.reopen` naming
    ///   nothing, observed at N. In progress and blocked are R1's own states of an open task, which R2's merge doesn't
    ///   hold and the projection keeps; R1's transition writes them, and an active task's return to open.
    /// - **R1's rules** decide the status against the corrected record. A refusal leaves the correction committed and
    ///   the status child refused. A status equal to the record's makes no R1 call: its child is taken in and changes
    ///   nothing.
    public static func update(
        _ id: TaskID, correction: TaskCorrection, status target: TaskStatus?, expectedRevision: Int64,
        by principal: Principal, context: LegacyRequestContext, in tx: LegacyTransaction
    ) throws -> UpdateEffect {
        guard let entity = R1Identity.entityID(fromUUID: id.rawValue) else { throw LegacyRouteError.unmapped(id) }
        var fields: [LegacyChange] = []
        func field(_ name: String, _ payload: ItemOperationPayload) throws {
            fields.append(try change("field:" + name, entity, payload, observedRevision: expectedRevision))
        }
        if let title = correction.title { try field("title", .taskEdit(.title(title))) }
        if let notes = correction.notes { try field("notes", .noteReplaceObserved(text: notes)) }
        if let priority = correction.priority { try field("priority", .taskEdit(.priority(priority.rawValue))) }
        let setsDeadline = correction.clearDeadline || correction.deadline != nil
        if setsDeadline {
            try field("deadline", .taskEdit(.deadline(correction.clearDeadline ? nil : correction.deadline.map(wire))))
        }
        if let minutes = correction.estimatedMinutes {
            try field("estimatedMinutes", .taskEdit(.estimate(Int64(minutes))))
        }
        if let confirmation = correction.confirmation {
            try field("confirmation", .taskEdit(.confirmation(confirmation.rawValue)))
        }
        var all = fields
        switch target {
        case .completed: all.append(try change(status, entity, .taskComplete))
        case .cancelled: all.append(try change(status, entity, .taskCancel))
        case .open: all.append(try change(status, entity, .taskReopen(reopens: []), observedRevision: expectedRevision))
        case .inProgress, .blocked, nil: break
        }
        guard var task = try tx.records.get(LisaTask.self, id: id) else { throw LegacyRouteError.notProjected(id) }
        // No child at all: an absent status, or an R1-only one (in progress, blocked) with no field.
        let set =
            all.isEmpty
            ? nil
            : try LegacyChildSet(
                datasetID: context.datasetID, scope: context.scope, requestID: context.requestID, changes: all)
        let signed = try set?.signed(with: tx.signer) ?? []
        var children: [LegacyChildDisposition] = []
        var changes: [DomainChange] = []
        if let set, !fields.isEmpty {
            children = try dispositions(
                try tx.intake(Array(signed.prefix(fields.count)), projecting: false), set: set, changes: fields)
            let before = task
            try tx.project(entity, forceRevision: true, markingDeadlineCorrected: setsDeadline)
            guard let corrected = try tx.records.get(LisaTask.self, id: id) else {
                throw LegacyRouteError.notProjected(id)
            }
            task = corrected
            try tx.records.insert(TaskService.audit("task.corrected", task, principal, tx.now))
            let material =
                before.priority != task.priority || before.deadline != task.deadline
                || before.confirmation != task.confirmation
            changes.append(.taskChanged(id, material: material))
        }
        let statusIndex = fields.count
        // Takes the status child in, when the target has one, recording its disposition.
        func takeStatusChild() throws {
            guard let set, all.count > statusIndex else { return }
            children += try dispositions(
                try tx.intake([signed[statusIndex]], projecting: true), set: set, changes: all, from: statusIndex)
        }
        guard let target, target != task.status else {
            try takeStatusChild()
            return UpdateEffect(
                task: task, children: children, setDigest: set?.setDigest, changes: changes, statusRefusal: nil)
        }
        do {
            try TaskService.requireOwnerOrDevice(principal)
            var probe = task
            try probe.transition(to: target, at: tx.now)
        } catch {
            if let set, all.count > statusIndex {
                children.append(
                    LegacyChildDisposition(
                        index: statusIndex, childID: set.childIDs[statusIndex], discriminator: status,
                        disposition: .refused))
            }
            return UpdateEffect(
                task: task, children: children, setDigest: set?.setDigest, changes: changes, statusRefusal: error)
        }
        try takeStatusChild()
        guard var written = try tx.records.get(LisaTask.self, id: id) else { throw LegacyRouteError.notProjected(id) }
        if written.status != target {
            // R1's own state of an open task (in progress, blocked, or back to open), which R2's merge doesn't hold.
            try written.transition(to: target, at: tx.now)
            if written.origin == .extracted { written.ownerCorrected.insert(.status) }
            written = try tx.records.update(written)
            try tx.recordProjectionRevision(written.revision.value, of: entity)
        }
        try tx.records.insert(TaskService.audit("task.\(target.rawValue)", written, principal, tx.now))
        switch target {
        case .completed: changes.append(.taskCompleted(id))
        case .cancelled: changes.append(.taskCancelled(id))
        case .open, .inProgress, .blocked: changes.append(.taskChanged(id, material: true))
        }
        return UpdateEffect(
            task: written, children: children, setDigest: set?.setDigest, changes: changes, statusRefusal: nil)
    }

    static func change(
        _ discriminator: String, _ entity: Identifier128, _ payload: ItemOperationPayload,
        observedRevision: Int64? = nil
    ) throws -> LegacyChange {
        LegacyChange(
            discriminator: discriminator, entityType: "task", entityID: entity, chain: "task:" + entity.hex,
            operationType: payload.operationType, payload: try payload.canonicalValue,
            observedRevision: observedRevision)
    }

    /// Each child's disposition from its intake outcome, in request order. Anything but a final receipt that applies
    /// the child is a failure of the conversion, which then keeps nothing.
    static func dispositions(
        _ outcomes: [CoreIntakeOutcome], set: LegacyChildSet, changes: [LegacyChange], from first: Int = 0
    ) throws -> [LegacyChildDisposition] {
        var result: [LegacyChildDisposition] = []
        for (offset, outcome) in outcomes.enumerated() {
            let index = first + offset
            guard case .receipted(let signed) = outcome else {
                throw LegacyRouteError.childNotApplied(index: index, outcome: String(describing: outcome))
            }
            let disposition: LegacyChildDisposition.Disposition
            switch try signed.receipt().outcome {
            case .accepted: disposition = .applied
            case .acceptedWithConflict: disposition = .appliedWithConflict
            case .rejected, .waitingForDependencies:
                throw LegacyRouteError.childNotApplied(index: index, outcome: String(describing: outcome))
            }
            result.append(
                LegacyChildDisposition(
                    index: index, childID: set.childIDs[index], discriminator: changes[index].discriminator,
                    disposition: disposition))
        }
        return result
    }

    /// R1's deadline in the wire form: an instant to the millisecond with its zone, or a date that never becomes a time.
    static func wire(_ deadline: Deadline) -> WireDeadline {
        switch deadline {
        case .at(let instant, let zone):
            .instant(unixMilliseconds: Int64((instant.timeIntervalSince1970 * 1_000).rounded()), zone: zone?.identifier)
        case .onDate(let date):
            .date(date.iso)
        }
    }
}
