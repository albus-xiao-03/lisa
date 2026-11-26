// A preference key's canonical merge state at Core (plan §8.3.1; docs/DECISIONS.md D-73): every accepted operation of
// the key, in commit order, merged by LisaMerge's `PreferenceMergeState`, whose rules are joins. A legacy child
// observed at a projection revision observes the horizon Core resolved it to (D-69), as in `CoreTaskFold`. The
// replica folds its canonical operations by the same rules.

import Foundation
import LisaMerge
import LisaSQLite
import LisaSyncProtocol

enum CorePreferenceFold {
    static let partition = "preferences"

    /// The key and view of the preference entity `entityID`, or `nil` when Core holds no accepted operation of it.
    static func view(_ entityID: Identifier128, in session: SQLiteSession) throws
        -> (key: String, view: PreferenceView)?
    {
        let rows = try session.query(
            """
            SELECT body, epoch_id, position, observed_epoch, observed_position FROM core_operations
            WHERE entity_type = 'preference' AND entity_id = ? AND state IN ('accepted', 'accepted_with_conflict')
            ORDER BY position
            """, [CoreColumns.id(entityID)])
        var state = PreferenceMergeState()
        var key: String?
        for row in rows {
            let envelope = try OperationEnvelope.decode(body: try CoreColumns.bytes(row[0]))
            guard PreferenceOperationPayload.operationTypes.contains(envelope.operationType) else { continue }
            let payload = try PreferenceOperationPayload(
                operationType: envelope.operationType, payload: envelope.payload)
            key = payload.key
            var observed = envelope.observed.map(ObservedCoverage.init) ?? .nothing
            if let position = row[4].integer {
                observed = ObservedCoverage(
                    horizon: try ObservedHorizon(
                        epochID: try CoreColumns.identifier(row[3]), partition: partition, position: position),
                    pieces: [])
            }
            state.apply(
                payload, id: envelope.operationID, observed: observed,
                commit: CommitPosition(
                    epochID: try CoreColumns.identifier(row[1]), partition: partition,
                    position: try CoreColumns.integer(row[2])))
        }
        guard let key else { return nil }
        return (key, state.view)
    }
}
