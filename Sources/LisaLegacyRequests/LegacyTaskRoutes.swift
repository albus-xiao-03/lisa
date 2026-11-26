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
    static func dispositions(_ outcomes: [CoreIntakeOutcome], set: LegacyChildSet, changes: [LegacyChange]) throws
        -> [LegacyChildDisposition]
    {
        var result: [LegacyChildDisposition] = []
        for (index, outcome) in outcomes.enumerated() {
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
