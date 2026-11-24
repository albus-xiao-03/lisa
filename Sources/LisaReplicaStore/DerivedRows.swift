// Derived rows and their membership records (plan §8.4.2), inside the caller's transaction. A row changes only for a
// position above its version; for every bucket an applied entry touches, the membership record says whether that
// bucket's proof delivered the row, and at which version, so the absence rule can tell a row a newer proof excluded
// from one still in flight through another bucket.

import Foundation
import LisaSQLite
import LisaSyncProtocol

/// Derived rows, inside the caller's transaction.
enum DerivedRows {
    /// Applies one record at `position`, as delivered through `partitions` (the entry's applied partitions).
    static func apply(
        _ record: DerivedRecord, at position: Int64, through partitions: [String], in session: SQLiteSession
    )
        throws
    {
        let id = ReplicaColumns.id(record.id)
        let current =
            try session.query(
                "SELECT version FROM derived_rows WHERE record_type = ? AND record_id = ?", [.text(record.type), id]
            ).first?.first?.integer
        let range = record.occurrence?.buckets
        if current.map({ position > $0 }) ?? true {
            let body: SQLiteValue
            if let row = record.row {
                body = .blob(Data(try CanonicalEncoder.encode(row, limits: CanonicalLimits(maxBytes: 1 << 16))))
            } else {
                body = .null
            }
            try session.query(
                """
                INSERT INTO derived_rows (record_type, record_id, version, body, first_bucket, last_bucket)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT (record_type, record_id) DO UPDATE SET version = excluded.version, body = excluded.body,
                  first_bucket = excluded.first_bucket, last_bucket = excluded.last_bucket
                """,
                [
                    .text(record.type), id, .integer(position), body,
                    ReplicaColumns.optionalInteger(range?.lowerBound),
                    ReplicaColumns.optionalInteger(range?.upperBound),
                ])
        }
        for partition in partitions {
            let member = CalendarBuckets.bucket(ofPartition: partition).map { range?.contains($0) ?? false } ?? false
            try setMembership(
                partition, record.type, record.id, version: member ? position : nil, from: position, in: session)
        }
    }

    /// Records that `partition`'s proof delivered the row at `version`, or no longer holds it (`nil`); never moves a
    /// membership back to an older position.
    static func setMembership(
        _ partition: String, _ type: String, _ id: Identifier128, version: Int64?, from position: Int64,
        in session: SQLiteSession
    ) throws {
        let existing =
            try session.query(
                "SELECT version FROM memberships WHERE partition = ? AND entity_type = ? AND entity_id = ?",
                [.text(partition), .text(type), ReplicaColumns.id(id)]
            ).first?.first?.integer
        if let existing, existing > position { return }
        if let version {
            try session.query(
                """
                INSERT INTO memberships (partition, entity_type, entity_id, version) VALUES (?, ?, ?, ?)
                ON CONFLICT (partition, entity_type, entity_id) DO UPDATE SET version = excluded.version
                """, [.text(partition), .text(type), ReplicaColumns.id(id), .integer(version)])
        } else {
            try session.query(
                "DELETE FROM memberships WHERE partition = ? AND entity_type = ? AND entity_id = ?",
                [.text(partition), .text(type), ReplicaColumns.id(id)])
        }
    }
}
