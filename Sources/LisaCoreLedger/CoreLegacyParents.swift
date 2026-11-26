// Core's legacy parents (plan §8.12.2): one per R1 request, keyed by caller scope and request ID. A conversion runs in
// one write transaction: the parent is looked up again (the same key and fingerprint replay the recorded answer, any
// other fingerprint is a mismatch, and nothing is converted twice), the route's conversion decides and takes in the
// Core-signed children through the ledger, and the parent is recorded with each child's disposition and the answer.
// Nothing of a conversion that fails is kept. The route semantics live in LisaLegacyRequests; this is the frame.

import Foundation
import LisaCrypto
import LisaPorts
import LisaSQLite
import LisaStore
import LisaSyncProtocol
import LisaTrust

/// What a parent says about a request before converting it.
public enum LegacyParentLookup: Hashable, Sendable {
    case unknown
    /// The same key and fingerprint: the recorded answer, replayed with `Lisa-Replayed: true`.
    case replay(status: Int, body: [UInt8])
    /// The recorded body has expired; the answer is a terminal reply built from current state.
    case bodyExpired(status: Int)
    /// The same key with another fingerprint: 422 `requestIDReused`.
    case mismatch
    /// The request waits for an administrative decision.
    case awaitingReview
}

/// One child's disposition, in request order.
public struct LegacyChildDisposition: Hashable, Sendable {
    public enum Disposition: String, Hashable, Sendable {
        case applied
        case appliedWithConflict = "applied_with_conflict"
        case alreadyPresent = "already_present"
        case refused
        case notReached = "not_reached"
        case heldForAdministrativeReview = "held_for_administrative_review"
        case pendingBehindReview = "pending_behind_review"
    }

    public let index: Int
    public let childID: Identifier128
    public let discriminator: String
    public let disposition: Disposition

    public init(index: Int, childID: Identifier128, discriminator: String, disposition: Disposition) {
        self.index = index
        self.childID = childID
        self.discriminator = discriminator
        self.disposition = disposition
    }
}

/// What a route's conversion decided.
public struct LegacyConversion: Hashable, Sendable {
    /// R1's status and body for this request.
    public let status: Int
    public let body: [UInt8]
    /// Every child of the complete set, decided or not; empty for a request R1 refuses before any change.
    public let children: [LegacyChildDisposition]
    public let setDigest: Digest256?

    public init(status: Int, body: [UInt8], children: [LegacyChildDisposition], setDigest: Digest256?) {
        self.status = status
        self.body = body
        self.children = children
        self.setDigest = setDigest
    }

    /// R1 records definite answers and nothing else (`APIRouter.isRecordable`).
    public var isRecordable: Bool { (200..<300).contains(status) || [400, 403, 404, 409, 413].contains(status) }
}

/// A conversion's view of the ledger, inside its one write transaction.
public struct LegacyTransaction {
    let ledger: CoreLedger
    let session: SQLiteSession
    let epoch: Identifier128
    let time: Int64
    /// R1's records, read and written in the same transaction.
    public let records: any RecordWriting

    /// Core's signing key, which signs every child.
    public var signer: any MessageSigning { ledger.signer }

    /// The conversion's time: the parent's, the children's decisions', and what R1's services would read as now for
    /// the records the conversion writes beside the projection, such as R1's audit events.
    public var now: Date { Date(timeIntervalSince1970: Double(time) / 1_000) }

    /// Takes Core-signed children into the ledger in this transaction, one outcome each, in order. A child Core's key
    /// didn't sign is `unverified`. Without `projecting`, applied children aren't projected into R1's records yet:
    /// `project` then writes the entity once, so a correction of several fields is one R1 revision step.
    public func intake(_ children: [SignedOperation], projecting: Bool = true) throws -> [CoreIntakeOutcome] {
        var outcomes: [CoreIntakeOutcome] = []
        for child in children {
            let envelope: OperationEnvelope
            do {
                envelope = try OperationSigning.verify(
                    child, dataset: ledger.datasetID, deviceKey: { _ in nil }, coreKey: ledger.signer.verifier)
            } catch {
                outcomes.append(.unverified(error))
                continue
            }
            try session.execute("SAVEPOINT legacy_intake")
            do {
                outcomes.append(
                    try ledger.intakeOne(
                        child, envelope: envelope, epoch: epoch, time: time, session: session, records: records,
                        project: projecting))
                try session.execute("RELEASE legacy_intake")
            } catch {
                try? session.execute("ROLLBACK TO legacy_intake")
                try? session.execute("RELEASE legacy_intake")
                throw error
            }
        }
        return outcomes
    }

    /// Projects a task's merged state into R1's record once, as one R1 service call: with `forceRevision`, the record
    /// is written, and its revision raised, even when no field changed, as R1's `TaskService.correct` does. With
    /// `markingDeadlineCorrected`, the deadline is marked owner-corrected whatever its value, as R1 marks it (D-72).
    public func project(_ entity: Identifier128, forceRevision: Bool, markingDeadlineCorrected: Bool = false) throws {
        let view = try CoreTaskFold.view(entity, in: session)
        let created = try CoreOperationRecords.creationTime(of: entity, in: session).map {
            Date(timeIntervalSince1970: Double($0) / 1_000)
        }
        let revision = try TaskProjection.project(
            view, entityID: entity, createdAt: created, commitTime: Date(timeIntervalSince1970: Double(time) / 1_000),
            into: records, force: forceRevision, markDeadlineCorrected: markingDeadlineCorrected)
        guard
            let position = try session.query("SELECT last_position FROM core_dataset WHERE singleton = 1").first?.first?
                .integer
        else { throw CoreLedgerError.corrupt("the dataset row") }
        try TaskProjection.recordRevision(revision, of: entity, at: position, in: session)
    }

    /// Records that R1's revision `revision` of `entity`, written by the conversion itself rather than the projection
    /// (an R1-only status of an open task, D-72), reflects every commit so far, so a later edit observed at it maps.
    public func recordProjectionRevision(_ revision: Int64, of entity: Identifier128) throws {
        guard
            let position = try session.query("SELECT last_position FROM core_dataset WHERE singleton = 1").first?.first?
                .integer
        else { throw CoreLedgerError.corrupt("the dataset row") }
        try TaskProjection.recordRevision(revision, of: entity, at: position, in: session)
    }
}

extension CoreLedger {
    /// What the parent of `(scope, requestID)` says about a request with `fingerprint`.
    public func legacyLookup(scope: String, requestID: String, fingerprint: String) throws(CoreLedgerError)
        -> LegacyParentLookup
    {
        let time = now()
        return try read { session, _ in
            try Self.lookup(scope: scope, requestID: requestID, fingerprint: fingerprint, time: time, session: session)
        }
    }

    /// Converts a request in one write transaction: a parent found again answers without converting; otherwise
    /// `convert` decides and takes in the children, and a recordable answer is recorded with the parent and every
    /// child's disposition, its body kept for `retentionDays`. An answer R1 wouldn't record (a 503, say) commits
    /// nothing, as a thrown error does.
    public func legacyConvert(
        scope: String, requestID: String, fingerprint: String, route: String, retentionDays: Int = 30,
        _ convert: (LegacyTransaction) throws -> LegacyConversion
    ) throws(CoreLedgerError) -> (lookup: LegacyParentLookup, conversion: LegacyConversion?) {
        let time = now()
        do {
            return try storage.records.ledgerWrite { session, records in
                let found = try Self.lookup(
                    scope: scope, requestID: requestID, fingerprint: fingerprint, time: time, session: session)
                guard found == .unknown else { return (found, nil) }
                try session.execute("SAVEPOINT legacy_conversion")
                let conversion: LegacyConversion
                do {
                    conversion = try convert(
                        LegacyTransaction(
                            ledger: self, session: session, epoch: try Self.epoch(in: session), time: time,
                            records: records))
                } catch {
                    try? session.execute("ROLLBACK TO legacy_conversion")
                    try? session.execute("RELEASE legacy_conversion")
                    throw error
                }
                guard conversion.isRecordable else {
                    try session.execute("ROLLBACK TO legacy_conversion")
                    try session.execute("RELEASE legacy_conversion")
                    return (.unknown, conversion)
                }
                try session.execute("RELEASE legacy_conversion")
                let waiting = conversion.children.contains { $0.disposition == .heldForAdministrativeReview }
                try session.query(
                    """
                    INSERT INTO core_legacy_parents (scope, request_id, fingerprint, route, origin_path, state,
                      child_count, set_digest, status, body, body_expires_at, created_at, completed_at)
                    VALUES (?, ?, ?, ?, 'v1', ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(scope), .text(requestID), .text(fingerprint), .text(route),
                        .text(waiting ? "awaiting_administrative_review" : "complete"),
                        .integer(Int64(conversion.children.count)),
                        conversion.setDigest.map { CoreColumns.digest($0) } ?? .null,
                        waiting ? .null : .integer(Int64(conversion.status)),
                        waiting ? .null : CoreColumns.bytes(conversion.body),
                        waiting ? .null : .integer(time + Int64(retentionDays) * 86_400_000), .integer(time),
                        waiting ? .null : .integer(time),
                    ])
                for child in conversion.children {
                    try session.query(
                        """
                        INSERT INTO core_legacy_children (scope, request_id, child_index, child_id, discriminator,
                          disposition)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                        [
                            .text(scope), .text(requestID), .integer(Int64(child.index)), CoreColumns.id(child.childID),
                            .text(child.discriminator), .text(child.disposition.rawValue),
                        ])
                }
                return (.unknown, conversion)
            }
        } catch {
            throw CoreLedgerError.classify(error)
        }
    }

    /// The commit position up to which R1's revision `revision` of a task reflects Core's commits, as projected.
    public func projectionPosition(of entity: Identifier128, revision: Int64) throws(CoreLedgerError) -> Int64? {
        try read { session, _ in
            try session.query(
                "SELECT position FROM core_projection_revisions WHERE entity_id = ? AND revision = ?",
                [CoreColumns.id(entity), .integer(revision)]
            ).first?.first?.integer
        }
    }

    /// Each child's disposition for the parent of `(scope, requestID)`, in request order.
    public func legacyChildren(scope: String, requestID: String) throws(CoreLedgerError) -> [LegacyChildDisposition] {
        try read { session, _ in
            try session.query(
                """
                SELECT child_index, child_id, discriminator, disposition FROM core_legacy_children
                WHERE scope = ? AND request_id = ? ORDER BY child_index
                """, [.text(scope), .text(requestID)]
            ).map { row in
                guard let disposition = LegacyChildDisposition.Disposition(rawValue: try CoreColumns.text(row[3]))
                else {
                    throw CoreLedgerError.corrupt("a legacy child")
                }
                return LegacyChildDisposition(
                    index: Int(try CoreColumns.integer(row[0])), childID: try CoreColumns.identifier(row[1]),
                    discriminator: try CoreColumns.text(row[2]), disposition: disposition)
            }
        }
    }

    static func lookup(scope: String, requestID: String, fingerprint: String, time: Int64, session: SQLiteSession)
        throws -> LegacyParentLookup
    {
        guard
            let row = try session.query(
                """
                SELECT fingerprint, state, status, body, body_expires_at FROM core_legacy_parents
                WHERE scope = ? AND request_id = ?
                """, [.text(scope), .text(requestID)]
            ).first
        else { return .unknown }
        guard try CoreColumns.text(row[0]) == fingerprint else { return .mismatch }
        guard try CoreColumns.text(row[1]) == "complete" else { return .awaitingReview }
        let status = Int(try CoreColumns.integer(row[2]))
        if case .blob(let body) = row[3], let expiry = row[4].integer, time < expiry {
            return .replay(status: status, body: [UInt8](body))
        }
        return .bodyExpired(status: status)
    }
}
