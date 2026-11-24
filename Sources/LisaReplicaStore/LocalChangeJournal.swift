// The local change journal and the local state generation (plan §8.6.3): every change that may alter the effective
// view appends `(generation, kind, references)` in the transaction that makes it, and the generation advances by one
// per change. Staging reads the ordered changes after any generation.

import LisaSQLite
import LisaSyncProtocol

/// Reading and appending local changes inside the caller's transaction.
enum LocalChangeJournal {
    /// The reference encoding's bound: a change names at most a page of operations and items.
    static let referenceLimits = CanonicalLimits(maxBytes: 1 << 20)

    /// The current local state generation.
    static func generation(in session: SQLiteSession) throws -> Int64 {
        guard
            let value = try session.query("SELECT local_generation FROM replica_identity WHERE singleton = 1").first?
                .first?.integer
        else { throw ReplicaStoreError.corrupt("the replica identity row is missing") }
        return value
    }

    /// Appends one change and advances the generation; returns the change's generation.
    @discardableResult
    static func append(
        _ kind: LocalChange.Kind, operations: [Identifier128], items: [ReplicaItemKey], in session: SQLiteSession
    ) throws -> Int64 {
        let next = try generation(in: session) + 1
        try session.query(
            "INSERT INTO local_changes (generation, kind, refs) VALUES (?, ?, ?)",
            [
                .integer(next), .text(kind.rawValue),
                ReplicaColumns.bytes(try encode(operations: operations, items: items)),
            ])
        try session.query("UPDATE replica_identity SET local_generation = ? WHERE singleton = 1", [.integer(next)])
        // Staged partition repairs keep up with every local change (§8.4.3 step 3). Their derived rows have no local
        // overlay yet, so keeping up is advancing the watermark; views and search entries joining them recompute here.
        try session.query("UPDATE repairs SET overlay_watermark = ?", [.integer(next)])
        return next
    }

    /// The changes after `generation`, oldest first, at most `limit`.
    static func changes(after generation: Int64, limit: Int, in session: SQLiteSession) throws -> [LocalChange] {
        try session.query(
            "SELECT generation, kind, refs FROM local_changes WHERE generation > ? ORDER BY generation LIMIT ?",
            [.integer(generation), .integer(Int64(limit))]
        ).map { row in
            guard let kind = LocalChange.Kind(rawValue: try ReplicaColumns.text(row[1])) else {
                throw ReplicaStoreError.corrupt("a local change kind")
            }
            let (operations, items) = try decode(ReplicaColumns.bytes(row[2]))
            return LocalChange(
                generation: try ReplicaColumns.integer(row[0]), kind: kind, operations: operations, items: items)
        }
    }

    static func encode(operations: [Identifier128], items: [ReplicaItemKey]) throws -> [UInt8] {
        let itemValues: [CanonicalValue] = try items.map { item in
            .object(
                try CanonicalObject([
                    ("entityID", .string(item.entityID.hex)), ("entityType", .string(item.entityType)),
                ]))
        }
        let object = try CanonicalObject([
            ("items", .array(itemValues)), ("operations", .array(operations.map { .string($0.hex) })),
        ])
        return try CanonicalEncoder.encode(.object(object), limits: referenceLimits)
    }

    static func decode(_ bytes: [UInt8]) throws -> ([Identifier128], [ReplicaItemKey]) {
        var reader = try CanonicalFieldReader(CanonicalDecoder.decode(bytes, limits: referenceLimits))
        let items = try reader.array("items").map { value in
            var fields = try CanonicalFieldReader(value)
            let item = ReplicaItemKey(
                entityType: try fields.string("entityType"), entityID: try Identifier128(hex: fields.string("entityID"))
            )
            try fields.finish()
            return item
        }
        let operations = try reader.array("operations").map { value in
            guard case .string(let hex) = value else { throw ReplicaStoreError.corrupt("a local change reference") }
            return try Identifier128(hex: hex)
        }
        try reader.finish()
        return (operations, items)
    }
}
