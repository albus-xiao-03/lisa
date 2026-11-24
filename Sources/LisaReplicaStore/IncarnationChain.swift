// The replica's incarnation chain (plan §8.1.1, §8.6.4): each launch that opens the replica records a new incarnation;
// sequences are allocated inside the transaction that stores the operation; an incarnation's first operation names
// the latest earlier incarnation that created an operation, with its last sequence. A restored copy of the replica
// therefore starts a new incarnation on its next launch and never repeats an identity: the chain shows the fork.

import LisaSQLite
import LisaSyncProtocol

/// Incarnation rows, inside the caller's transaction.
enum IncarnationChain {
    /// Records `incarnation` as the latest launch.
    static func start(_ incarnation: Identifier128, at time: Int64, in session: SQLiteSession) throws {
        try session.query(
            """
            INSERT INTO incarnations (ordinal, incarnation_id, started_at)
            VALUES ((SELECT coalesce(max(ordinal), 0) + 1 FROM incarnations), ?, ?)
            """,
            [ReplicaColumns.id(incarnation), .integer(time)])
    }

    /// The next sequence of `incarnation` and, for its first, the link its operation names. Writes nothing.
    static func next(for incarnation: Identifier128, in session: SQLiteSession) throws -> (
        sequence: Int64, previous: IncarnationLink?
    ) {
        guard
            let row = try session.query(
                "SELECT ordinal, last_sequence FROM incarnations WHERE incarnation_id = ?",
                [ReplicaColumns.id(incarnation)]
            ).first
        else { throw ReplicaStoreError.corrupt("the current incarnation is missing") }
        let sequence = try ReplicaColumns.integer(row[1]) + 1
        guard sequence == 1 else { return (sequence, nil) }
        guard
            let earlier = try session.query(
                """
                SELECT incarnation_id, last_sequence FROM incarnations
                WHERE ordinal < ? AND last_sequence >= 1 ORDER BY ordinal DESC LIMIT 1
                """,
                [.integer(try ReplicaColumns.integer(row[0]))]
            ).first
        else { return (1, nil) }
        return (
            1,
            try IncarnationLink(
                incarnationID: ReplicaColumns.identifier(earlier[0]), lastSequence: ReplicaColumns.integer(earlier[1]))
        )
    }

    /// Records that `sequence` was used; on the first, also the link it named. Refuses anything but the next one.
    static func use(
        _ sequence: Int64, previous: IncarnationLink?, for incarnation: Identifier128, in session: SQLiteSession
    ) throws {
        if sequence == 1 {
            try session.query(
                """
                UPDATE incarnations SET last_sequence = 1, previous_incarnation_id = ?, previous_last_sequence = ?
                WHERE incarnation_id = ? AND last_sequence = 0
                """,
                [
                    ReplicaColumns.optionalID(previous?.incarnationID),
                    ReplicaColumns.optionalInteger(previous?.lastSequence), ReplicaColumns.id(incarnation),
                ])
        } else {
            try session.query(
                "UPDATE incarnations SET last_sequence = ? WHERE incarnation_id = ? AND last_sequence = ?",
                [.integer(sequence), ReplicaColumns.id(incarnation), .integer(sequence - 1)])
        }
        guard session.changes == 1 else { throw ReplicaStoreError.corrupt("sequence \(sequence) isn't the next one") }
    }

    /// The chain in launch order.
    static func records(in session: SQLiteSession) throws -> [IncarnationRecord] {
        try session.query(
            """
            SELECT ordinal, incarnation_id, started_at, last_sequence, previous_incarnation_id, previous_last_sequence
            FROM incarnations ORDER BY ordinal
            """
        ).map { row in
            var previous: IncarnationLink?
            if let link = try ReplicaColumns.optionalIdentifier(row[4]),
                let last = ReplicaColumns.optionalInteger(row[5])
            {
                previous = try IncarnationLink(incarnationID: link, lastSequence: last)
            }
            return IncarnationRecord(
                ordinal: try ReplicaColumns.integer(row[0]), incarnationID: try ReplicaColumns.identifier(row[1]),
                startedAt: try ReplicaColumns.integer(row[2]), lastSequence: try ReplicaColumns.integer(row[3]),
                previous: previous)
        }
    }
}
