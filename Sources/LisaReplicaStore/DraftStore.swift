// Draft rows (plan §8.6.2): the command as canonical JSON under the operation ID it will be signed with, its
// original input and time, why it is a draft, and whether it is held, signed or discarded.

import LisaSQLite
import LisaSyncProtocol

/// Draft rows, inside the caller's transaction.
enum DraftStore {
    static func insert(
        _ operationID: Identifier128, command: LocalCommand, createdAt: Int64, reason: ReplicaDraft.Reason,
        in session: SQLiteSession
    ) throws {
        try session.query(
            """
            INSERT INTO drafts (operation_id, command, original_input, created_at, reason, state)
            VALUES (?, ?, ?, ?, ?, 'held')
            """,
            [
                ReplicaColumns.id(operationID), ReplicaColumns.bytes(try encode(command)),
                ReplicaColumns.optionalText(command.originalInput), .integer(createdAt), .text(reason.rawValue),
            ])
    }

    /// The oldest held draft, in save order.
    static func firstHeld(in session: SQLiteSession) throws -> ReplicaDraft? {
        try session.query(
            """
            SELECT operation_id, command, original_input, created_at, reason, state FROM drafts
            WHERE state = 'held' ORDER BY rowid LIMIT 1
            """
        ).first.map(decode)
    }

    /// Every draft, in save order.
    static func all(in session: SQLiteSession) throws -> [ReplicaDraft] {
        try session.query(
            "SELECT operation_id, command, original_input, created_at, reason, state FROM drafts ORDER BY rowid"
        ).map(decode)
    }

    static func markSigned(_ operationID: Identifier128, in session: SQLiteSession) throws {
        try session.query(
            "UPDATE drafts SET state = 'signed' WHERE operation_id = ? AND state = 'held'",
            [ReplicaColumns.id(operationID)])
        guard session.changes == 1 else { throw ReplicaStoreError.corrupt("the draft wasn't held") }
    }

    /// The command without its original input, which has its own column.
    static func encode(_ command: LocalCommand) throws -> [UInt8] {
        var pairs: [(String, CanonicalValue)] = [
            ("dependencies", .array(command.dependencies.map { .string($0.hex) })),
            ("entityID", .string(command.item.entityID.hex)), ("entityType", .string(command.item.entityType)),
            ("operationType", .string(command.operationType)), ("payload", command.payload),
        ]
        if let observed = command.observed { pairs.append(("observed", try observed.canonicalValue)) }
        return try CanonicalEncoder.encode(.object(try CanonicalObject(pairs)), limits: .operationBody)
    }

    static func decode(_ bytes: [UInt8], originalInput: String?) throws -> LocalCommand {
        var reader = try CanonicalFieldReader(CanonicalDecoder.decode(bytes, limits: .operationBody))
        let dependencies = try reader.array("dependencies").map { value in
            guard case .string(let hex) = value else { throw ReplicaStoreError.corrupt("a draft dependency") }
            return try Identifier128(hex: hex)
        }
        let item = ReplicaItemKey(
            entityType: try reader.string("entityType"), entityID: try Identifier128(hex: reader.string("entityID")))
        let operationType = try reader.string("operationType")
        let payload = try reader.value("payload")
        let observed = try reader.optionalValue("observed").map { try ObservedSet(canonicalValue: $0) }
        try reader.finish()
        return LocalCommand(
            item: item, operationType: operationType, payload: payload, dependencies: dependencies, observed: observed,
            originalInput: originalInput)
    }

    private static func decode(_ row: [SQLiteValue]) throws -> ReplicaDraft {
        guard let reason = ReplicaDraft.Reason(rawValue: try ReplicaColumns.text(row[4])),
            let state = ReplicaDraft.State(rawValue: try ReplicaColumns.text(row[5]))
        else { throw ReplicaStoreError.corrupt("a draft's reason or state") }
        return ReplicaDraft(
            operationID: try ReplicaColumns.identifier(row[0]),
            command: try decode(ReplicaColumns.bytes(row[1]), originalInput: ReplicaColumns.optionalText(row[2])),
            createdAt: try ReplicaColumns.integer(row[3]), reason: reason, state: state)
    }
}
