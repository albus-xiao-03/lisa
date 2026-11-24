// The action ledger, `actions.sqlite` (plan §10.8 "The action ledger: no real action twice"): the intent is committed
// before any external I/O, `submitting` before the first byte, and every outcome as soon as it is known. Resume
// observes and reconciles; only an owner's typed authorization allows exactly one further attempt of an ambiguous
// action.

import Foundation
import LisaSQLite

/// The run's ledger of logical actions.
public final class VerifyActionLedger: @unchecked Sendable {
    let database: SQLiteDatabase

    public init(path: String) throws(VerifyError) {
        do {
            database = try SQLiteDatabase(path: path)
            try database.writeTransaction { session in
                try session.execute(
                    """
                    CREATE TABLE IF NOT EXISTS actions(
                        action_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, case_id TEXT NOT NULL,
                        position INTEGER NOT NULL, kind TEXT NOT NULL, target_alias TEXT NOT NULL,
                        operation_id TEXT NOT NULL, slot TEXT, confirmation_digest TEXT NOT NULL, retry_of TEXT,
                        state TEXT NOT NULL, provider_reference TEXT, outcome TEXT,
                        created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
                    CREATE TABLE IF NOT EXISTS confirmations(
                        run_id TEXT NOT NULL, digest TEXT NOT NULL, action_ids TEXT NOT NULL,
                        confirmed_at TEXT NOT NULL, PRIMARY KEY(run_id, digest));
                    CREATE TABLE IF NOT EXISTS events(
                        seq INTEGER PRIMARY KEY AUTOINCREMENT, action_id TEXT NOT NULL, at TEXT NOT NULL,
                        event TEXT NOT NULL, detail TEXT NOT NULL);
                    """)
            }
        } catch {
            throw .ledger("can't open \(path): \(error)")
        }
    }

    // MARK: Confirmations

    /// Records that the owner confirmed exactly these actions (their digest and IDs).
    public func recordConfirmation(_ actions: [VerifyPlannedAction], in run: VerifyRunID) throws(VerifyError) -> String
    {
        let digest = VerifyPlannedAction.confirmationDigest(actions, in: run)
        let ids = actions.map { $0.actionID(in: run) }.sorted().joined(separator: "\n")
        try write { session in
            try session.query(
                "INSERT OR IGNORE INTO confirmations(run_id, digest, action_ids, confirmed_at) VALUES (?, ?, ?, ?)",
                [.text(run.text), .text(digest), .text(ids), .text(Self.now())])
        }
        return digest
    }

    /// The confirmation digest covering `actionID`, if any confirmation listed it.
    public func confirmation(covering actionID: String, in run: VerifyRunID) throws(VerifyError) -> String? {
        let rows = try read { session in
            try session.query(
                "SELECT digest, action_ids FROM confirmations WHERE run_id = ? ORDER BY confirmed_at", [.text(run.text)]
            )
        }
        for row in rows {
            let ids = (row[1].text ?? "").split(separator: "\n").map(String.init)
            if ids.contains(actionID) { return row[0].text }
        }
        return nil
    }

    // MARK: Transitions

    /// Step 1: commits the intent before any external I/O. Recording the same planned action again returns the
    /// existing record; a different action under the same ID is refused.
    @discardableResult
    public func recordIntent(_ planned: VerifyPlannedAction, in run: VerifyRunID, confirmationDigest: String)
        throws(VerifyError) -> VerifyActionRecord
    {
        let id = planned.actionID(in: run)
        if let existing = try record(id) {
            guard existing.kind == planned.kind, existing.operationID == planned.operationID,
                existing.targetAlias == planned.targetAlias, existing.slot == planned.slot
            else { throw .ledger("\(id) is already recorded with other identities") }
            return existing
        }
        let now = Self.now()
        try write { session in
            try session.query(
                """
                INSERT INTO actions(action_id, run_id, case_id, position, kind, target_alias, operation_id, slot,
                    confirmation_digest, retry_of, state, provider_reference, outcome, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 'intent', NULL, NULL, ?, ?)
                """,
                [
                    .text(id), .text(run.text), .text(planned.caseID.text), .integer(Int64(planned.position)),
                    .text(planned.kind.rawValue), .text(planned.targetAlias), .text(planned.operationID),
                    planned.slot.map { .text($0) } ?? .null, .text(confirmationDigest), .text(now), .text(now),
                ])
            try Self.log(session, id, "intent", confirmationDigest)
        }
        guard let created = try record(id) else { throw .ledger("\(id) vanished after its intent") }
        return created
    }

    /// Step 2: commits `submitting` before the first byte leaves. Only an `intent` can start submitting.
    public func markSubmitting(_ actionID: String) throws(VerifyError) {
        try transition(actionID, from: [.intent], to: .submitting, reference: nil, outcome: nil, event: "submitting")
    }

    /// The provider accepted the action (directly, or found by observation during resume).
    public func recordAccepted(_ actionID: String, providerReference: String?, outcome: String) throws(VerifyError) {
        try transition(
            actionID, from: [.intent, .submitting, .ambiguous], to: .accepted, reference: providerReference,
            outcome: outcome, event: "accepted")
    }

    /// The provider definitely refused it: nothing was accepted.
    public func recordRefused(_ actionID: String, outcome: String) throws(VerifyError) {
        try transition(actionID, from: [.submitting], to: .refused, reference: nil, outcome: outcome, event: "refused")
    }

    /// Step 3: `submitting` with no outcome and no evidence found.
    public func markAmbiguous(_ actionID: String, evidence: String) throws(VerifyError) {
        try transition(
            actionID, from: [.submitting], to: .ambiguous, reference: nil, outcome: evidence, event: "ambiguous")
    }

    /// Step 4: the owner's typed phrase authorizes exactly one further attempt of an ambiguous action, recorded as
    /// `<action ID>.r2` (an intent the caller then submits). Anything else is refused and changes nothing.
    public func authorizeRetry(_ actionID: String, typedPhrase: String) throws(VerifyError) -> VerifyActionRecord {
        guard typedPhrase == "may duplicate \(actionID)" else {
            throw .retryNotAuthorized("type exactly: may duplicate \(actionID)")
        }
        guard let original = try record(actionID) else { throw .retryNotAuthorized("no action \(actionID)") }
        guard original.state == .ambiguous else {
            throw .retryNotAuthorized("\(actionID) is \(original.state.rawValue), not ambiguous")
        }
        guard original.retryOf == nil else { throw .retryNotAuthorized("\(actionID) is itself a retry") }
        let retryID = actionID + ".r2"
        guard try record(retryID) == nil else { throw .retryNotAuthorized("\(retryID) already exists") }
        let now = Self.now()
        try write { session in
            try session.query(
                """
                INSERT INTO actions(action_id, run_id, case_id, position, kind, target_alias, operation_id, slot,
                    confirmation_digest, retry_of, state, provider_reference, outcome, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'intent', NULL, NULL, ?, ?)
                """,
                [
                    .text(retryID), .text(original.runID.text), .text(original.caseID.text),
                    .integer(Int64(original.position)), .text(original.kind.rawValue), .text(original.targetAlias),
                    .text(original.operationID), original.slot.map { .text($0) } ?? .null,
                    .text(original.confirmationDigest), .text(actionID), .text(now), .text(now),
                ])
            try session.query(
                "UPDATE actions SET state = 'superseded', updated_at = ? WHERE action_id = ? AND state = 'ambiguous'",
                [.text(now), .text(actionID)])
            try Self.log(session, actionID, "retry-authorized", retryID)
        }
        guard let retry = try record(retryID) else { throw .ledger("\(retryID) vanished after its authorization") }
        return retry
    }

    // MARK: Reading

    public func record(_ actionID: String) throws(VerifyError) -> VerifyActionRecord? {
        try read { session in
            try session.query("SELECT \(Self.columns) FROM actions WHERE action_id = ?", [.text(actionID)])
        }.first.map(Self.decode)
    }

    /// Every action of a run, ordered by case, position and ID.
    public func records(in run: VerifyRunID) throws(VerifyError) -> [VerifyActionRecord] {
        try read { session in
            try session.query(
                "SELECT \(Self.columns) FROM actions WHERE run_id = ? ORDER BY case_id, position, action_id",
                [.text(run.text)])
        }.map(Self.decode)
    }

    /// The actions resume must observe: `intent` or `submitting`.
    public func unresolved(in run: VerifyRunID) throws(VerifyError) -> [VerifyActionRecord] {
        try records(in: run).filter { $0.state.isUnresolved }
    }

    // MARK: Internals

    static let columns =
        "action_id, run_id, case_id, position, kind, target_alias, operation_id, slot, confirmation_digest, "
        + "retry_of, state, provider_reference, outcome, created_at, updated_at"

    static func decode(_ row: [SQLiteValue]) -> VerifyActionRecord {
        // Rows are written only by this type, so every value has its expected shape.
        VerifyActionRecord(
            actionID: row[0].text!, runID: try! VerifyRunID(row[1].text!), caseID: try! VerifyCaseID(row[2].text!),
            position: Int(row[3].integer!), kind: VerifyActionKind(rawValue: row[4].text!)!,
            targetAlias: row[5].text!, operationID: row[6].text!, slot: row[7].text, confirmationDigest: row[8].text!,
            retryOf: row[9].text, state: VerifyActionState(rawValue: row[10].text!)!, providerReference: row[11].text,
            outcome: row[12].text, createdAt: row[13].text!, updatedAt: row[14].text!)
    }

    private func transition(
        _ actionID: String, from allowed: Set<VerifyActionState>, to state: VerifyActionState, reference: String?,
        outcome: String?, event: String
    ) throws(VerifyError) {
        guard let current = try record(actionID) else { throw .ledger("no action \(actionID)") }
        guard allowed.contains(current.state) else {
            throw .ledger("\(actionID) can't become \(state.rawValue) from \(current.state.rawValue)")
        }
        try write { session in
            try session.query(
                """
                UPDATE actions SET state = ?, provider_reference = COALESCE(?, provider_reference),
                    outcome = COALESCE(?, outcome), updated_at = ?
                WHERE action_id = ? AND state = ?
                """,
                [
                    .text(state.rawValue), reference.map { .text($0) } ?? .null, outcome.map { .text($0) } ?? .null,
                    .text(Self.now()), .text(actionID), .text(current.state.rawValue),
                ])
            guard session.changes == 1 else { throw VerifyError.ledger("\(actionID) changed concurrently") }
            try Self.log(session, actionID, event, outcome ?? "")
        }
    }

    private static func log(_ session: SQLiteSession, _ actionID: String, _ event: String, _ detail: String) throws {
        try session.query(
            "INSERT INTO events(action_id, at, event, detail) VALUES (?, ?, ?, ?)",
            [.text(actionID), .text(now()), .text(event), .text(detail)])
    }

    private func write(_ body: (SQLiteSession) throws -> Void) throws(VerifyError) {
        do {
            try database.writeTransaction(body)
        } catch let error as VerifyError {
            throw error
        } catch {
            throw .ledger("\(error)")
        }
    }

    private func read(_ body: (SQLiteSession) throws -> [[SQLiteValue]]) throws(VerifyError) -> [[SQLiteValue]] {
        do {
            return try database.readTransaction(body)
        } catch {
            throw .ledger("\(error)")
        }
    }

    static func now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
