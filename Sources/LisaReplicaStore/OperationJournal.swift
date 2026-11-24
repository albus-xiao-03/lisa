// The operation journal's rows (plan §8.6.1, §8.2.1): exact signed bytes, digest and origin, the Core-side state and
// receipt, and the overlay flag; the lookups the duplicate rules need; and the security events they raise.

import LisaSQLite
import LisaSyncProtocol

/// Journal rows, inside the caller's transaction.
enum OperationJournal {
    static let columns = """
        operation_id, digest, body, signature, origin_device, origin_incarnation, origin_sequence, entity_type, \
        entity_id, operation_type, source, state, overlay, receipt, commit_epoch, commit_position, stored_generation, \
        from_draft
        """

    /// Stores a new operation: pending and an overlay, or `revoked` and out of the view.
    static func insert(
        _ operation: SignedOperation, envelope: OperationEnvelope, digest: Digest256, source: JournalEntry.Source,
        generation: Int64, fromDraft: Bool, state: ReplicaOperationState = .pending, in session: SQLiteSession
    ) throws {
        let triple = envelope.origin.deviceTriple
        try session.query(
            """
            INSERT INTO operations (operation_id, digest, body, signature, origin_device, origin_incarnation,
              origin_sequence, entity_type, entity_id, operation_type, source, state, overlay, stored_generation, from_draft)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                ReplicaColumns.id(envelope.operationID), ReplicaColumns.digest(digest),
                ReplicaColumns.bytes(operation.body), ReplicaColumns.bytes(operation.signature),
                ReplicaColumns.optionalID(triple?.device), ReplicaColumns.optionalID(triple?.incarnation),
                ReplicaColumns.optionalInteger(triple?.sequence), .text(envelope.entityType),
                ReplicaColumns.id(envelope.entityID), .text(envelope.operationType), .text(source.rawValue),
                .text(state.rawValue), .integer(state == .revoked ? 0 : 1), .integer(generation),
                .integer(fromDraft ? 1 : 0),
            ])
    }

    static func entry(_ operationID: Identifier128, in session: SQLiteSession) throws -> JournalEntry? {
        try session.query("SELECT \(columns) FROM operations WHERE operation_id = ?", [ReplicaColumns.id(operationID)])
            .first.map(decode)
    }

    /// Every entry, in the order this replica stored them.
    static func entries(in session: SQLiteSession) throws -> [JournalEntry] {
        try session.query("SELECT \(columns) FROM operations ORDER BY stored_generation").map(decode)
    }

    /// The entries of `item` still in the effective view, in the order this replica stored them.
    static func overlays(for item: ReplicaItemKey, in session: SQLiteSession) throws -> [JournalEntry] {
        try session.query(
            """
            SELECT \(columns) FROM operations
            WHERE entity_type = ? AND entity_id = ? AND overlay = 1 ORDER BY stored_generation
            """,
            [.text(item.entityType), ReplicaColumns.id(item.entityID)]
        ).map(decode)
    }

    static func known(byID operationID: Identifier128, in session: SQLiteSession) throws -> KnownOperation? {
        try session.query(
            """
            SELECT operation_id, digest, origin_device, origin_incarnation, origin_sequence FROM operations
            WHERE operation_id = ?
            """,
            [ReplicaColumns.id(operationID)]
        ).first.map(decodeKnown)
    }

    static func known(byOrigin triple: OriginTriple, in session: SQLiteSession) throws -> KnownOperation? {
        try session.query(
            """
            SELECT operation_id, digest, origin_device, origin_incarnation, origin_sequence FROM operations
            WHERE origin_device = ? AND origin_incarnation = ? AND origin_sequence = ?
            """,
            [ReplicaColumns.id(triple.device), ReplicaColumns.id(triple.incarnation), .integer(triple.sequence)]
        ).first.map(decodeKnown)
    }

    /// Records a receipt's state, bytes and position; `overlay` is whether the entry stays in the effective view.
    static func record(_ receipt: ReplicaReceipt, overlay: Bool, in session: SQLiteSession) throws {
        try session.query(
            """
            UPDATE operations SET state = ?, receipt = ?, commit_epoch = ?, commit_position = ?, overlay = ?
            WHERE operation_id = ?
            """,
            [
                .text(receipt.state.rawValue), ReplicaColumns.bytes(receipt.signedBytes),
                ReplicaColumns.optionalID(receipt.epochID), ReplicaColumns.optionalInteger(receipt.position),
                .integer(overlay ? 1 : 0), ReplicaColumns.id(receipt.operationID),
            ])
    }

    static func recordSecurityEvent(
        _ kind: ReplicaSecurityEvent.Kind, operationID: Identifier128, arrivingDigest: Digest256,
        known: KnownOperation, at time: Int64, in session: SQLiteSession
    ) throws {
        try session.query(
            """
            INSERT INTO security_events (kind, operation_id, arriving_digest, known_operation_id, known_digest,
              recorded_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(kind.rawValue), ReplicaColumns.id(operationID), ReplicaColumns.digest(arrivingDigest),
                ReplicaColumns.id(known.operationID), ReplicaColumns.digest(known.digest), .integer(time),
            ])
    }

    static func securityEvents(in session: SQLiteSession) throws -> [ReplicaSecurityEvent] {
        try session.query(
            """
            SELECT kind, operation_id, arriving_digest, known_operation_id, known_digest, recorded_at
            FROM security_events ORDER BY event_id
            """
        ).map { row in
            guard let kind = ReplicaSecurityEvent.Kind(rawValue: try ReplicaColumns.text(row[0])) else {
                throw ReplicaStoreError.corrupt("a security event kind")
            }
            return ReplicaSecurityEvent(
                kind: kind, operationID: try ReplicaColumns.identifier(row[1]),
                arrivingDigest: try ReplicaColumns.digest(row[2]),
                knownOperationID: try ReplicaColumns.identifier(row[3]),
                knownDigest: try ReplicaColumns.digest(row[4]), recordedAt: try ReplicaColumns.integer(row[5]))
        }
    }

    private static func decodeKnown(_ row: [SQLiteValue]) throws -> KnownOperation {
        var triple: OriginTriple?
        if let device = try ReplicaColumns.optionalIdentifier(row[2]),
            let incarnation = try ReplicaColumns.optionalIdentifier(row[3]),
            let sequence = ReplicaColumns.optionalInteger(row[4])
        {
            triple = OriginTriple(device: device, incarnation: incarnation, sequence: sequence)
        }
        return KnownOperation(
            operationID: try ReplicaColumns.identifier(row[0]), digest: try ReplicaColumns.digest(row[1]),
            originTriple: triple)
    }

    private static func decode(_ row: [SQLiteValue]) throws -> JournalEntry {
        guard let source = JournalEntry.Source(rawValue: try ReplicaColumns.text(row[10])),
            let state = ReplicaOperationState(rawValue: try ReplicaColumns.text(row[11]))
        else { throw ReplicaStoreError.corrupt("a journal entry's source or state") }
        var origin: OriginTriple?
        if let device = try ReplicaColumns.optionalIdentifier(row[4]),
            let incarnation = try ReplicaColumns.optionalIdentifier(row[5]),
            let sequence = ReplicaColumns.optionalInteger(row[6])
        {
            origin = OriginTriple(device: device, incarnation: incarnation, sequence: sequence)
        }
        return JournalEntry(
            operation: try SignedOperation(body: ReplicaColumns.bytes(row[2]), signature: ReplicaColumns.bytes(row[3])),
            operationID: try ReplicaColumns.identifier(row[0]), digest: try ReplicaColumns.digest(row[1]),
            origin: origin,
            item: ReplicaItemKey(
                entityType: try ReplicaColumns.text(row[7]), entityID: try ReplicaColumns.identifier(row[8])),
            operationType: try ReplicaColumns.text(row[9]), source: source, state: state,
            isOverlay: try ReplicaColumns.integer(row[12]) == 1, receipt: ReplicaColumns.optionalBytes(row[13]),
            commitEpoch: try ReplicaColumns.optionalIdentifier(row[14]),
            commitPosition: ReplicaColumns.optionalInteger(row[15]),
            storedGeneration: try ReplicaColumns.integer(row[16]), fromDraft: try ReplicaColumns.integer(row[17]) == 1)
    }
}
