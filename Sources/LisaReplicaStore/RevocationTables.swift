// Device revocations on the replica (plan §8.1.3, §8.6.1; R2-L17): the union of every revocation learned from a
// verified roster, and the relayed operations a revocation takes out of the effective view.

import LisaSQLite
import LisaSyncProtocol

/// Revocation rows, inside the caller's transaction.
enum RevocationTables {
    /// Whether any revocation of `device` is recorded.
    static func isRevoked(_ device: Identifier128, in session: SQLiteSession) throws -> Bool {
        try !session.query("SELECT 1 FROM revocations WHERE device_id = ? LIMIT 1", [ReplicaColumns.id(device)])
            .isEmpty
    }

    static func contains(device: Identifier128, epochID: Identifier128, position: Int64, in session: SQLiteSession)
        throws -> Bool
    {
        try !session.query(
            "SELECT 1 FROM revocations WHERE device_id = ? AND epoch_id = ? AND position = ?",
            [ReplicaColumns.id(device), ReplicaColumns.id(epochID), .integer(position)]
        ).isEmpty
    }

    static func insert(
        device: Identifier128, epochID: Identifier128, position: Int64, learnedAt: Int64, generation: Int64,
        in session: SQLiteSession
    ) throws {
        try session.query(
            """
            INSERT INTO revocations (device_id, epoch_id, position, learned_at, learned_generation)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                ReplicaColumns.id(device), ReplicaColumns.id(epochID), .integer(position), .integer(learnedAt),
                .integer(generation),
            ])
    }

    /// The relayed operations of `device` that Core hasn't decided and canonical state doesn't hold, in the order this
    /// replica stored them: the pending effects a revocation leaves unauthorized.
    static func unauthorizedPending(of device: Identifier128, in session: SQLiteSession) throws -> [(
        operationID: Identifier128, item: ReplicaItemKey
    )] {
        try session.query(
            """
            SELECT o.operation_id, o.entity_type, o.entity_id FROM operations o
            WHERE o.origin_device = ? AND o.source = 'relayed'
              AND o.state IN ('pending', 'submitted', 'waiting_for_dependencies')
              AND NOT EXISTS (SELECT 1 FROM canonical_operations c WHERE c.operation_id = o.operation_id)
            ORDER BY o.stored_generation
            """, [ReplicaColumns.id(device)]
        ).map { row in
            guard let type = row[1].text else { throw ReplicaStoreError.corrupt("an operation's entity type") }
            return (
                try ReplicaColumns.identifier(row[0]),
                ReplicaItemKey(entityType: type, entityID: try ReplicaColumns.identifier(row[2]))
            )
        }
    }

    static func all(in session: SQLiteSession) throws -> [ReplicaRevocation] {
        try session.query(
            """
            SELECT device_id, epoch_id, position, learned_at, learned_generation FROM revocations
            ORDER BY learned_generation, device_id, epoch_id, position
            """
        ).map { row in
            ReplicaRevocation(
                deviceID: try ReplicaColumns.identifier(row[0]), epochID: try ReplicaColumns.identifier(row[1]),
                position: try ReplicaColumns.integer(row[2]), learnedAt: try ReplicaColumns.integer(row[3]),
                learnedGeneration: try ReplicaColumns.integer(row[4]))
        }
    }
}
