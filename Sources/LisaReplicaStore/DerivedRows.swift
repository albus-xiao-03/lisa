// Derived rows and their membership records (plan §8.4.2, §8.4.3), inside the caller's transaction. A row has one
// version per generation: generation 0 holds what pages delivered, and each partition repair stages its snapshot's
// rows in its own generation, invisible until published. Readers take a row's newest version among published
// generations, and a partition's membership from that partition's published generation. For every bucket an entry
// touches, the membership record says whether that bucket's proof delivered the row and at which version.

import Foundation
import LisaSQLite
import LisaSyncProtocol

/// Derived rows, inside the caller's transaction.
enum DerivedRows {
    /// The published generations: 0, and each partition's published generation.
    static let published = "(SELECT 0 UNION SELECT published_generation FROM partition_cursors)"

    /// The newest version of a row among published generations.
    static func newestPublishedVersion(_ type: String, _ id: Identifier128, in session: SQLiteSession) throws -> Int64?
    {
        try session.query(
            "SELECT max(version) FROM derived_rows WHERE record_type = ? AND record_id = ? AND generation IN \(published)",
            [.text(type), ReplicaColumns.id(id)]
        ).first?.first?.integer
    }

    /// Applies one record at `position` into `generation` (0 for pages), delivered through each partition into that
    /// partition's membership generation. A page's row changes only above the newest published version; a repair's
    /// staged row only above its own generation's.
    static func apply(
        _ record: DerivedRecord, at position: Int64, generation: Int64,
        through partitions: [(partition: String, generation: Int64)], in session: SQLiteSession
    ) throws {
        let id = ReplicaColumns.id(record.id)
        let current: Int64? =
            generation == 0
            ? try newestPublishedVersion(record.type, record.id, in: session)
            : try session.query(
                "SELECT version FROM derived_rows WHERE record_type = ? AND record_id = ? AND generation = ?",
                [.text(record.type), id, .integer(generation)]
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
                INSERT INTO derived_rows (record_type, record_id, generation, version, body, first_bucket, last_bucket)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (record_type, record_id, generation) DO UPDATE SET version = excluded.version,
                  body = excluded.body, first_bucket = excluded.first_bucket, last_bucket = excluded.last_bucket
                """,
                [
                    .text(record.type), id, .integer(generation), .integer(position), body,
                    ReplicaColumns.optionalInteger(range?.lowerBound),
                    ReplicaColumns.optionalInteger(range?.upperBound),
                ])
        }
        for (partition, membershipGeneration) in partitions {
            let member = CalendarBuckets.bucket(ofPartition: partition).map { range?.contains($0) ?? false } ?? false
            try setMembership(
                partition, generation: membershipGeneration, record.type, record.id, version: member ? position : nil,
                from: position, in: session)
        }
    }

    /// Records that `partition`'s proof in `generation` delivered the row at `version`, or no longer holds it (`nil`);
    /// never moves a membership back to an older position.
    static func setMembership(
        _ partition: String, generation: Int64, _ type: String, _ id: Identifier128, version: Int64?,
        from position: Int64, in session: SQLiteSession
    ) throws {
        let key: [SQLiteValue] = [.text(partition), .integer(generation), .text(type), ReplicaColumns.id(id)]
        let existing =
            try session.query(
                """
                SELECT version FROM memberships
                WHERE partition = ? AND generation = ? AND entity_type = ? AND entity_id = ?
                """, key
            ).first?.first?.integer
        if let existing, existing > position { return }
        if let version {
            try session.query(
                """
                INSERT INTO memberships (partition, generation, entity_type, entity_id, version) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (partition, generation, entity_type, entity_id) DO UPDATE SET version = excluded.version
                """, key + [.integer(version)])
        } else {
            try session.query(
                "DELETE FROM memberships WHERE partition = ? AND generation = ? AND entity_type = ? AND entity_id = ?",
                key)
        }
    }
}
