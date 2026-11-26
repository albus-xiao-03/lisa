// A preference key's effective view on a replica (plan §8.3.1; docs/DECISIONS.md D-73): its canonical operations from
// Core, with the horizon Core served for a legacy child (D-69), and the journal's applied, unrejected operations not yet
// canonical, merged by `PreferenceMergeState` as Core folds them.

import LisaMerge
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

extension ReplicaStore {
    /// The effective view of the preference `key`, or `nil` when the replica holds no operation of it.
    public func preferenceView(key: String) throws(ReplicaStoreError) -> PreferenceView? {
        try read { session in try Self.preferenceView(key: key, in: session) }
    }

    /// The effective view of the preference `key` inside the caller's transaction.
    public static func preferenceView(key: String, in session: SQLiteSession) throws -> PreferenceView? {
        let entityType = PreferenceEntity.entityType
        let entityID = ReplicaColumns.id(PreferenceEntity.id(forKey: key))
        let partition = CollectionPartition.name(forEntityType: entityType) ?? "preferences"
        let canonical = try session.query(
            """
            SELECT body, epoch_id, position, observed_epoch, observed_partition, observed_position
            FROM canonical_operations WHERE entity_type = ? AND entity_id = ?
            """, [.text(entityType), entityID])
        let journal = try session.query(
            """
            SELECT o.body, o.commit_epoch, o.commit_position, NULL, NULL, NULL FROM operations o
            JOIN causal_decisions d ON d.operation_id = o.operation_id AND d.decision = 'applied'
            WHERE o.entity_type = ? AND o.entity_id = ? AND o.state NOT IN ('rejected', 'revoked')
              AND NOT EXISTS (SELECT 1 FROM canonical_operations c WHERE c.operation_id = o.operation_id)
            """, [.text(entityType), entityID])
        let rows = canonical + journal
        guard !rows.isEmpty else { return nil }
        var state = PreferenceMergeState()
        for row in rows {
            let envelope = try OperationEnvelope.decode(body: ReplicaColumns.bytes(row[0]))
            guard PreferenceOperationPayload.operationTypes.contains(envelope.operationType) else { continue }
            let payload = try PreferenceOperationPayload(
                operationType: envelope.operationType, payload: envelope.payload)
            var commit: CommitPosition?
            if let epoch = try ReplicaColumns.optionalIdentifier(row[1]),
                let position = ReplicaColumns.optionalInteger(row[2])
            {
                commit = CommitPosition(epochID: epoch, partition: partition, position: position)
            }
            var observed = envelope.observed.map(ObservedCoverage.init) ?? .nothing
            if let horizon = try CanonicalTables.horizon(epoch: row[3], partition: row[4], position: row[5]) {
                observed = ObservedCoverage(horizon: horizon, pieces: [])
            }
            state.apply(payload, id: envelope.operationID, observed: observed, commit: commit)
        }
        return state.view
    }
}
