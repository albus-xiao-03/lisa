// Canonical state, cursors and deferred pages (plan §8.4.2, §8.4.3), inside the caller's transaction.

import LisaSQLite
import LisaSyncProtocol

/// The replica's canonical tables.
enum CanonicalTables {
    static func cursor(_ partition: String, in session: SQLiteSession) throws -> PartitionCursor? {
        guard
            let row = try session.query(
                "SELECT epoch_id, cursor, repairing FROM partition_cursors WHERE partition = ?", [.text(partition)]
            ).first
        else { return nil }
        return PartitionCursor(
            partition: partition, epochID: try ReplicaColumns.identifier(row[0]),
            position: try ReplicaColumns.integer(row[1]), isRepairing: try ReplicaColumns.integer(row[2]) == 1)
    }

    /// The generation whose membership records `partition` reads (0 until a repair publishes one).
    static func publishedGeneration(_ partition: String, in session: SQLiteSession) throws -> Int64 {
        try session.query("SELECT published_generation FROM partition_cursors WHERE partition = ?", [.text(partition)])
            .first?.first?.integer ?? 0
    }

    /// Sets a cursor; within one epoch it never moves backward.
    static func setCursor(
        _ partition: String, epoch: Identifier128, position: Int64, repairing: Bool, in session: SQLiteSession
    ) throws {
        if let current = try cursor(partition, in: session), current.epochID == epoch, current.position > position {
            throw ReplicaStoreError.corrupt("a cursor would move backward")
        }
        try session.query(
            """
            INSERT INTO partition_cursors (partition, epoch_id, cursor, repairing) VALUES (?, ?, ?, ?)
            ON CONFLICT (partition) DO UPDATE SET epoch_id = excluded.epoch_id, cursor = excluded.cursor,
              repairing = excluded.repairing
            """, [.text(partition), ReplicaColumns.id(epoch), .integer(position), .integer(repairing ? 1 : 0)])
    }

    static func deferPage(
        _ signed: SignedChangePage, page: ChangePage, for partition: String, in session: SQLiteSession
    )
        throws
    {
        try session.query(
            """
            INSERT INTO deferred_pages (partition, from_position, to_position, page, signature) VALUES (?, ?, ?, ?, ?)
            """,
            [
                .text(partition), .integer(page.fromPosition), .integer(page.toPosition),
                ReplicaColumns.bytes(signed.body), ReplicaColumns.bytes(signed.signature),
            ])
    }

    /// The deferred pages of `partition`, oldest interval first, and removes them.
    static func takeDeferred(_ partition: String, in session: SQLiteSession) throws -> [SignedChangePage] {
        let rows = try session.query(
            "SELECT page, signature FROM deferred_pages WHERE partition = ? ORDER BY from_position, page_id",
            [.text(partition)])
        try session.query("DELETE FROM deferred_pages WHERE partition = ?", [.text(partition)])
        return try rows.map { row in
            try SignedChangePage(body: ReplicaColumns.bytes(row[0]), signature: ReplicaColumns.bytes(row[1]))
        }
    }

    /// The row version of `item`: the position of the last change it reflects.
    static func rowVersion(_ item: ReplicaItemKey, in session: SQLiteSession) throws -> Int64? {
        try session.query(
            "SELECT version FROM canonical_rows WHERE entity_type = ? AND entity_id = ?",
            [.text(item.entityType), ReplicaColumns.id(item.entityID)]
        ).first?.first?.integer
    }

    static func setRowVersion(_ item: ReplicaItemKey, _ version: Int64, in session: SQLiteSession) throws {
        try session.query(
            """
            INSERT INTO canonical_rows (entity_type, entity_id, version) VALUES (?, ?, ?)
            ON CONFLICT (entity_type, entity_id) DO UPDATE SET version = excluded.version
            WHERE excluded.version > canonical_rows.version
            """, [.text(item.entityType), ReplicaColumns.id(item.entityID), .integer(version)])
    }

    static func insertCanonical(
        _ operation: SignedOperation, envelope: OperationEnvelope, epoch: Identifier128, position: Int64,
        decision: ChangeEntry.Decision, in session: SQLiteSession
    ) throws {
        try session.query(
            """
            INSERT OR IGNORE INTO canonical_operations
              (operation_id, entity_type, entity_id, body, signature, epoch_id, position, decision)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ReplicaColumns.id(envelope.operationID), .text(envelope.entityType),
                ReplicaColumns.id(envelope.entityID),
                ReplicaColumns.bytes(operation.body), ReplicaColumns.bytes(operation.signature),
                ReplicaColumns.id(epoch), .integer(position), .text(decision.rawValue),
            ])
    }
}
