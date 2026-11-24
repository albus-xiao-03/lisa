// Follow-up rows (plan §8.6.1 step 7), written in the same transaction as the change that needs them.

import LisaSQLite
import LisaSyncProtocol

/// Follow-up rows, inside the caller's transaction.
enum FollowUpQueue {
    static func add(
        _ kind: ReplicaFollowUp.Kind, _ operationID: Identifier128, generation: Int64, in session: SQLiteSession
    ) throws {
        try session.query(
            "INSERT OR IGNORE INTO follow_up (kind, reference, created_generation) VALUES (?, ?, ?)",
            [.text(kind.rawValue), ReplicaColumns.id(operationID), .integer(generation)])
    }

    static func remove(_ kind: ReplicaFollowUp.Kind, _ operationID: Identifier128, in session: SQLiteSession) throws {
        try session.query(
            "DELETE FROM follow_up WHERE kind = ? AND reference = ?",
            [.text(kind.rawValue), ReplicaColumns.id(operationID)])
    }

    static func all(in session: SQLiteSession) throws -> [ReplicaFollowUp] {
        try session.query("SELECT kind, reference, created_generation FROM follow_up ORDER BY follow_up_id").map {
            row in
            guard let kind = ReplicaFollowUp.Kind(rawValue: try ReplicaColumns.text(row[0])) else {
                throw ReplicaStoreError.corrupt("a follow-up kind")
            }
            return ReplicaFollowUp(
                kind: kind, operationID: try ReplicaColumns.identifier(row[1]),
                createdGeneration: try ReplicaColumns.integer(row[2]))
        }
    }
}
