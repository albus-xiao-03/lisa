// The Core ledger's operation rows (plan §8.4.1, §8.2.1): exact signed bytes, digest and origin, the decision with its
// reason, commit position and current receipt; the lookups the duplicate rules need; and their security events.

import Foundation
import LisaDomain
import LisaPorts
import LisaSQLite
import LisaSyncProtocol

/// A refusal under the duplicate rules, as Core records it.
public struct CoreSecurityEvent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case identityReuse = "identity_reuse"
        case sequenceReuse = "sequence_reuse"
    }

    public let kind: Kind
    /// The arriving operation's ID and digest.
    public let operationID: Identifier128
    public let arrivingDigest: Digest256
    /// The stored operation it collided with.
    public let knownOperationID: Identifier128
    public let knownDigest: Digest256
    /// Unix milliseconds.
    public let recordedAt: Int64

    public init(
        kind: Kind, operationID: Identifier128, arrivingDigest: Digest256, knownOperationID: Identifier128,
        knownDigest: Digest256, recordedAt: Int64
    ) {
        self.kind = kind
        self.operationID = operationID
        self.arrivingDigest = arrivingDigest
        self.knownOperationID = knownOperationID
        self.knownDigest = knownDigest
        self.recordedAt = recordedAt
    }
}

enum CoreOperationRecords {
    static func known(byID operationID: Identifier128, in session: SQLiteSession) throws -> KnownOperation? {
        try session.query(
            """
            SELECT operation_id, digest, origin_device, origin_incarnation, origin_sequence FROM core_operations
            WHERE operation_id = ?
            """, [CoreColumns.id(operationID)]
        ).first.map(decodeKnown)
    }

    static func known(byOrigin triple: OriginTriple, in session: SQLiteSession) throws -> KnownOperation? {
        try session.query(
            """
            SELECT operation_id, digest, origin_device, origin_incarnation, origin_sequence FROM core_operations
            WHERE origin_device = ? AND origin_incarnation = ? AND origin_sequence = ?
            """, [CoreColumns.id(triple.device), CoreColumns.id(triple.incarnation), .integer(triple.sequence)]
        ).first.map(decodeKnown)
    }

    /// The stored receipt's bytes (body, then signature).
    static func receipt(_ operationID: Identifier128, in session: SQLiteSession) throws -> [UInt8]? {
        guard
            let value = try session.query(
                "SELECT receipt FROM core_operations WHERE operation_id = ?", [CoreColumns.id(operationID)]
            ).first?.first
        else { return nil }
        if case .null = value { return nil }
        return try CoreColumns.bytes(value)
    }

    /// The stored operation's exact signed bytes.
    static func operation(_ operationID: Identifier128, in session: SQLiteSession) throws -> SignedOperation? {
        guard
            let row = try session.query(
                "SELECT body, signature FROM core_operations WHERE operation_id = ?", [CoreColumns.id(operationID)]
            ).first
        else { return nil }
        return try SignedOperation(body: try CoreColumns.bytes(row[0]), signature: try CoreColumns.bytes(row[1]))
    }

    /// Stores an arriving operation, undecided.
    static func insertWaiting(
        _ operation: SignedOperation, envelope: OperationEnvelope, digest: Digest256, epoch: Identifier128,
        receivedAt: Int64, in session: SQLiteSession
    ) throws {
        let triple = envelope.origin.deviceTriple
        try session.query(
            """
            INSERT INTO core_operations (operation_id, digest, body, signature, origin_device, origin_incarnation,
              origin_sequence, entity_type, entity_id, operation_type, state, epoch_id, received_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'waiting', ?, ?)
            """,
            [
                CoreColumns.id(envelope.operationID), CoreColumns.digest(digest), CoreColumns.bytes(operation.body),
                CoreColumns.bytes(operation.signature), CoreColumns.optionalID(triple?.device),
                CoreColumns.optionalID(triple?.incarnation), CoreColumns.optionalInteger(triple?.sequence),
                .text(envelope.entityType), CoreColumns.id(envelope.entityID), .text(envelope.operationType),
                CoreColumns.id(epoch), .integer(receivedAt),
            ])
    }

    /// Records a decision at its commit position.
    static func decide(
        _ operationID: Identifier128, state: String, reason: String?, position: Int64, in session: SQLiteSession
    ) throws {
        try session.query(
            "UPDATE core_operations SET state = ?, reason = ?, position = ? WHERE operation_id = ?",
            [.text(state), CoreColumns.optionalText(reason), .integer(position), CoreColumns.id(operationID)])
    }

    /// Resolves a legacy child's "observed at projection revision N" when Core decides it (plan §8.3.2, §8.12.2): the
    /// horizon of the state R1's revision N of the entity reflected, kept with the operation for every later fold. A
    /// revision the map doesn't hold resolves to nothing, so the child observes nothing and conflicts rather than
    /// superseding pieces it may not have seen.
    static func resolveObservedRevision(of envelope: OperationEnvelope, in session: SQLiteSession) throws {
        guard let revision = envelope.observed?.projectionRevision,
            let row = try session.query(
                "SELECT epoch_id, position FROM core_projection_revisions WHERE entity_id = ? AND revision = ?",
                [CoreColumns.id(envelope.entityID), .integer(revision)]
            ).first
        else { return }
        try session.query(
            "UPDATE core_operations SET observed_epoch = ?, observed_position = ? WHERE operation_id = ?",
            [row[0], row[1], CoreColumns.id(envelope.operationID)])
    }

    /// Resolves a legacy preference child's observation when Core decides it (D-74): R1's record of the key as Core
    /// found it, the record R1's `set`, `confirm` and delete act on. A record observes the horizon its revision reflects;
    /// a revision the map doesn't hold resolves to nothing, as in `resolveObservedRevision`. An absent record observes
    /// every commit before the child: all that is left of the key then is deletes, replaced writes and model
    /// suggestions, which an R1 write replaces too.
    static func resolveFoundRecord(
        of envelope: OperationEnvelope, key: String, position: Int64, records: any RecordWriting,
        in session: SQLiteSession
    ) throws {
        let horizon: [SQLiteValue]
        if let found = try records.find(Preference.self, RecordQuery.all.filter("key", equals: key)).first {
            guard
                let row = try session.query(
                    "SELECT epoch_id, position FROM core_projection_revisions WHERE entity_id = ? AND revision = ?",
                    [CoreColumns.id(envelope.entityID), .integer(found.revision.value)]
                ).first
            else { return }
            horizon = [row[0], row[1]]
        } else {
            horizon = [CoreColumns.id(try CoreLedger.epoch(in: session)), .integer(position - 1)]
        }
        try session.query(
            "UPDATE core_operations SET observed_epoch = ?, observed_position = ? WHERE operation_id = ?",
            horizon + [CoreColumns.id(envelope.operationID)])
    }

    static func setReceipt(_ operationID: Identifier128, _ receipt: SignedCoreReceipt, in session: SQLiteSession)
        throws
    {
        try session.query(
            "UPDATE core_operations SET receipt = ? WHERE operation_id = ?",
            [CoreColumns.bytes(receipt.storedBytes), CoreColumns.id(operationID)])
    }

    static func recordSecurityEvent(
        _ kind: CoreSecurityEvent.Kind, operationID: Identifier128, arrivingDigest: Digest256, known: KnownOperation,
        at time: Int64, in session: SQLiteSession
    ) throws {
        try session.query(
            """
            INSERT INTO core_security_events (kind, operation_id, arriving_digest, known_operation_id, known_digest,
              recorded_at) VALUES (?, ?, ?, ?, ?, ?)
            """,
            [
                .text(kind.rawValue), CoreColumns.id(operationID), CoreColumns.digest(arrivingDigest),
                CoreColumns.id(known.operationID), CoreColumns.digest(known.digest), .integer(time),
            ])
    }

    static func securityEvents(in session: SQLiteSession) throws -> [CoreSecurityEvent] {
        try session.query(
            """
            SELECT kind, operation_id, arriving_digest, known_operation_id, known_digest, recorded_at
            FROM core_security_events ORDER BY event_id
            """
        ).map { row in
            guard let kind = CoreSecurityEvent.Kind(rawValue: try CoreColumns.text(row[0])) else {
                throw CoreLedgerError.corrupt("a security event's kind")
            }
            return CoreSecurityEvent(
                kind: kind, operationID: try CoreColumns.identifier(row[1]),
                arrivingDigest: try CoreColumns.digest(row[2]), knownOperationID: try CoreColumns.identifier(row[3]),
                knownDigest: try CoreColumns.digest(row[4]), recordedAt: try CoreColumns.integer(row[5]))
        }
    }

    /// Whether Core accepted any operation of the item.
    static func hasAccepted(_ entityType: String, _ entityID: Identifier128, in session: SQLiteSession) throws -> Bool {
        try !session.query(
            """
            SELECT 1 FROM core_operations WHERE entity_type = ? AND entity_id = ?
              AND state IN ('accepted', 'accepted_with_conflict') LIMIT 1
            """, [.text(entityType), CoreColumns.id(entityID)]
        ).isEmpty
    }

    /// The display time of the item's accepted creation, in Unix milliseconds.
    static func creationTime(of entityID: Identifier128, in session: SQLiteSession) throws -> Int64? {
        guard
            let body = try session.query(
                """
                SELECT body FROM core_operations WHERE entity_type = 'task' AND entity_id = ?
                  AND operation_type = 'task.create' AND state IN ('accepted', 'accepted_with_conflict')
                ORDER BY position LIMIT 1
                """, [CoreColumns.id(entityID)]
            ).first?.first
        else { return nil }
        return try OperationEnvelope.decode(body: try CoreColumns.bytes(body)).createdAt
    }

    private static func decodeKnown(_ row: [SQLiteValue]) throws -> KnownOperation {
        var triple: OriginTriple?
        if let device = try CoreColumns.optionalIdentifier(row[2]),
            let incarnation = try CoreColumns.optionalIdentifier(row[3]), let sequence = row[4].integer
        {
            triple = OriginTriple(device: device, incarnation: incarnation, sequence: sequence)
        }
        return KnownOperation(
            operationID: try CoreColumns.identifier(row[0]), digest: try CoreColumns.digest(row[1]),
            originTriple: triple)
    }
}
