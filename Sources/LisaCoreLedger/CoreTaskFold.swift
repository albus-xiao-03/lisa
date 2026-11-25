// A task's canonical merge state at Core (plan §8.3): every accepted operation of the task, in commit order, merged by
// LisaMerge's `TaskMergeState`, whose rules are joins, so the order changes nothing. A paged resolution group applies
// atomically, as its last page observing every page's candidates, once its pages are all present and the SHA-256 of
// their sorted, concatenated IDs matches the list digest (§8.3.2). The replica folds its canonical operations by the
// same rules.

import Foundation
import LisaCrypto
import LisaMerge
import LisaSQLite
import LisaSyncProtocol

enum CoreTaskFold {
    static let partition = "tasks"

    /// The view of `entityID`, or `nil` when Core holds no accepted operation of it.
    static func view(_ entityID: Identifier128, in session: SQLiteSession) throws -> TaskView? {
        let rows = try session.query(
            """
            SELECT body, epoch_id, position FROM core_operations
            WHERE entity_type = 'task' AND entity_id = ? AND state IN ('accepted', 'accepted_with_conflict')
            ORDER BY position
            """, [CoreColumns.id(entityID)])
        guard !rows.isEmpty else { return nil }
        var state = TaskMergeState()
        var groups:
            [Identifier128: [(envelope: OperationEnvelope, payload: ItemOperationPayload, commit: CommitPosition)]] =
                [:]
        for row in rows {
            let envelope = try OperationEnvelope.decode(body: try CoreColumns.bytes(row[0]))
            guard ItemOperationPayload.operationTypes.contains(envelope.operationType) else { continue }
            let payload = try ItemOperationPayload(operationType: envelope.operationType, payload: envelope.payload)
            let commit = CommitPosition(
                epochID: try CoreColumns.identifier(row[1]), partition: partition,
                position: try CoreColumns.integer(row[2]))
            if case .conflictResolve = payload, let group = envelope.observed?.group {
                groups[group.groupID, default: []].append((envelope, payload, commit))
                continue
            }
            state.apply(
                payload, id: envelope.operationID, observed: envelope.observed.map(ObservedCoverage.init) ?? .nothing,
                commit: commit)
        }
        for pages in groups.values {
            guard let resolution = completeGroup(pages.map { ($0.envelope, $0.payload) }),
                let last = pages.first(where: { $0.envelope.operationID == resolution.operationID })
            else { continue }
            state.apply(last.payload, id: resolution.operationID, observed: resolution.observed, commit: last.commit)
        }
        return state.view
    }

    /// The fields an operation writes that hold more than one candidate in `view`: a conflict it leaves open.
    static func leavesConflict(_ payload: ItemOperationPayload, in view: TaskView) -> Bool {
        switch payload {
        case .taskCreate:
            return view.title.count > 1 || view.priority.count > 1 || view.deadline.count > 1
                || view.estimate.count > 1 || view.splittable.count > 1 || view.confirmation.count > 1
        case .taskEdit(let value):
            switch value {
            case .title: return view.title.count > 1
            case .priority: return view.priority.count > 1
            case .deadline: return view.deadline.count > 1
            case .estimate: return view.estimate.count > 1
            case .splittable: return view.splittable.count > 1
            case .confirmation: return view.confirmation.count > 1
            }
        case .taskComplete, .taskCancel: return view.status == .completedAndCancelled
        default: return false
        }
    }

    /// A complete, consistent resolution group: every index of one count and list digest present once, one field, and
    /// the SHA-256 of the sorted, concatenated IDs of all pages equal to the list digest.
    static func completeGroup(_ pages: [(envelope: OperationEnvelope, payload: ItemOperationPayload)])
        -> (operationID: Identifier128, observed: ObservedCoverage)?
    {
        guard let first = pages.first?.envelope.observed?.group, pages.count == Int(first.count) else { return nil }
        var byIndex: [Int64: (envelope: OperationEnvelope, payload: ItemOperationPayload)] = [:]
        var field: TaskField?
        for page in pages {
            guard let group = page.envelope.observed?.group, group.count == first.count,
                group.listDigest == first.listDigest, byIndex[group.index] == nil,
                case .conflictResolve(let pageField, _) = page.payload, field == nil || field == pageField
            else { return nil }
            field = pageField
            byIndex[group.index] = page
        }
        guard let last = byIndex[first.count], (1...first.count).allSatisfy({ byIndex[$0] != nil }) else { return nil }
        let ids = Set(pages.flatMap { $0.envelope.observed?.pieces ?? [] }).sorted {
            $0.bytes.lexicographicallyPrecedes($1.bytes)
        }
        guard [UInt8](Digests.sha256(Data(ids.flatMap(\.bytes)))) == first.listDigest.bytes else { return nil }
        return (last.envelope.operationID, ObservedCoverage(horizon: last.envelope.observed?.horizon, pieces: Set(ids)))
    }
}
