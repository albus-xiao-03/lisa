// Administrative decisions on held v1 requests (plan §8.12.2 "lisa core legacy resolve"; docs/DECISIONS.md D-76). A
// decision runs in one Core transaction: the typed token is looked up over every hold Core ever issued; a decided hold
// replays its recorded outcome and changes nothing; anything that isn't the parent's waiting hold moves nothing; and
// the waiting hold is decided by the route, its decision recorded with what it moved. A refusal also leaves a
// content-free refusal guard, so R1's 403 answers the same request for the dataset's life.

import Foundation
import LisaCrypto
import LisaSQLite
import LisaSyncProtocol
import LisaTrust

public enum LegacyDecisionAction: String, Hashable, Sendable {
    case apply
    case refuse
}

/// The hold a decision is about, and the request it holds.
public struct LegacyHoldContext: Sendable {
    public let datasetID: Identifier128
    public let scope: String
    public let requestID: String
    public let fingerprint: String
    public let route: String
    /// The original request bytes, kept while the parent waits.
    public let requestBody: [UInt8]
    public let childIndex: Int
    public let childID: Identifier128
    public let generation: Int64
    /// The hold's token as the administrative terminal shows it.
    public let token: String
}

/// What the route decided about a hold.
public struct LegacyDecision: Sendable {
    /// The children whose disposition changed, the held one first. A child left `held_for_administrative_review` is the
    /// next hold.
    public let children: [LegacyChildDisposition]
    /// R1's answer, once the request is complete.
    public let status: Int?
    public let body: [UInt8]?
    /// What the administrative terminal prints.
    public let outcome: String
    /// The answer is the administrator's refusal, kept as a refusal guard (§8.14.8).
    public let isRefusal: Bool

    public init(
        children: [LegacyChildDisposition], status: Int?, body: [UInt8]?, outcome: String, isRefusal: Bool
    ) {
        self.children = children
        self.status = status
        self.body = body
        self.outcome = outcome
        self.isRefusal = isRefusal
    }
}

/// What `legacyResolve` did.
public enum LegacyResolution: Hashable, Sendable {
    /// The waiting hold was decided; the outcome is what the decision moved.
    case decided(outcome: String)
    /// The same decision again: its recorded outcome, nothing changed.
    case replayed(outcome: String)
    /// Another decision on a decided hold: nothing changed.
    case alreadyDecided(String)
    /// Not a waiting hold's token: mistyped, ambiguous, stale or forged. Nothing moved.
    case refused(String)
}

extension CoreLedger {
    /// Decides the hold `token` names, in one write transaction (§8.12.2 "lisa core legacy resolve"): a replay, a
    /// refusal that moves nothing, or `decide`'s decision recorded with the hold and the parent. The answer of a
    /// completed request is recorded for `retentionDays`; a refusal's also as a refusal guard.
    public func legacyResolve(
        token: String, action: LegacyDecisionAction, actor: String, retentionDays: Int = 30,
        _ decide: (LegacyTransaction, LegacyHoldContext) throws -> LegacyDecision
    ) throws(CoreLedgerError) -> LegacyResolution {
        let time = now()
        do {
            return try storage.records.ledgerWrite { session, records in
                guard let prefix = LegacyDecisionToken.typedPrefix(token) else {
                    return .refused("\(token) isn't a decision token.")
                }
                let shown = LegacyDecisionToken.prefix + prefix
                let rows = try session.query(
                    """
                    SELECT decision_key, token, scope, request_id, child_index, child_id, hold_generation, action,
                      decided_at, outcome
                    FROM core_legacy_holds WHERE substr(token, 1, ?) = ? ORDER BY held_at, scope, request_id
                    """, [.integer(Int64(prefix.count)), .text(prefix)])
                guard let row = rows.first else { return .refused("\(shown) doesn't name a waiting change.") }
                guard rows.count == 1 else {
                    let longer = min(52, prefix.count + LegacyDecisionToken.stepCharacters)
                    let matches = try rows.map { match in
                        "\(try CoreColumns.text(match[2])) request \(try CoreColumns.text(match[3])) as "
                            + LegacyDecisionToken.prefix + String(try CoreColumns.text(match[1]).prefix(longer))
                    }
                    return .refused("\(shown) names more than one change: " + matches.joined(separator: "; ") + ".")
                }
                let scope = try CoreColumns.text(row[2])
                let requestID = try CoreColumns.text(row[3])
                let index = Int(try CoreColumns.integer(row[4]))
                let generation = try CoreColumns.integer(row[6])
                if case .text(let decided) = row[7] {
                    let outcome = try CoreColumns.text(row[9])
                    if decided == action.rawValue { return .replayed(outcome: outcome) }
                    let at = Date(timeIntervalSince1970: Double(try CoreColumns.integer(row[8])) / 1_000)
                    return .alreadyDecided(
                        "Already decided: \(decided == "apply" ? "applied" : "refused") by \(shown) at "
                            + "\(at.ISO8601Format()); nothing changed.")
                }
                guard
                    let parent = try session.query(
                        """
                        SELECT fingerprint, route, state, request_body FROM core_legacy_parents
                        WHERE scope = ? AND request_id = ?
                        """, [.text(scope), .text(requestID)]
                    ).first, try CoreColumns.text(parent[2]) == "awaiting_administrative_review",
                    case .blob(let body) = parent[3],
                    try session.query(
                        "SELECT max(hold_generation) FROM core_legacy_holds WHERE scope = ? AND request_id = ?",
                        [.text(scope), .text(requestID)]
                    ).first?.first?.integer == generation
                else { return .refused("\(shown) doesn't name a waiting change.") }
                let context = LegacyHoldContext(
                    datasetID: datasetID, scope: scope, requestID: requestID,
                    fingerprint: try CoreColumns.text(parent[0]), route: try CoreColumns.text(parent[1]),
                    requestBody: [UInt8](body), childIndex: index, childID: try CoreColumns.identifier(row[5]),
                    generation: generation, token: shown)
                try session.execute("SAVEPOINT legacy_decision")
                let decision: LegacyDecision
                do {
                    decision = try decide(
                        LegacyTransaction(
                            ledger: self, session: session, epoch: try Self.epoch(in: session), time: time,
                            records: records),
                        context)
                } catch {
                    try? session.execute("ROLLBACK TO legacy_decision")
                    try? session.execute("RELEASE legacy_decision")
                    throw error
                }
                try session.execute("RELEASE legacy_decision")
                try Self.record(
                    decision, of: context, dataset: datasetID, action: action, actor: actor, decisionKey: row[0],
                    time: time, retentionDays: retentionDays, session: session)
                return .decided(outcome: decision.outcome)
            }
        } catch {
            throw CoreLedgerError.classify(error)
        }
    }

    /// Writes a decision: the children it moved, the decision record on the hold, the next hold if it reached one, and
    /// on completion the parent's answer, with a refusal guard for the administrator's refusal.
    static func record(
        _ decision: LegacyDecision, of context: LegacyHoldContext, dataset: Identifier128,
        action: LegacyDecisionAction, actor: String, decisionKey: SQLiteValue, time: Int64, retentionDays: Int,
        session: SQLiteSession
    ) throws {
        for child in decision.children {
            try session.query(
                """
                UPDATE core_legacy_children SET disposition = ?
                WHERE scope = ? AND request_id = ? AND child_index = ?
                """,
                [
                    .text(child.disposition.rawValue), .text(context.scope), .text(context.requestID),
                    .integer(Int64(child.index)),
                ])
            if child.disposition == .heldForAdministrativeReview {
                try insertHold(
                    dataset: dataset, scope: context.scope, requestID: context.requestID, child: child,
                    generation: context.generation + 1, time: time, session: session)
            }
        }
        try session.query(
            """
            UPDATE core_legacy_holds SET decision_id = ?, action = ?, actor = ?, decided_at = ?, outcome = ?
            WHERE decision_key = ?
            """,
            [
                CoreColumns.id(.random()), .text(action.rawValue), .text(actor), .integer(time),
                .text(decision.outcome), decisionKey,
            ])
        guard let status = decision.status, let body = decision.body else { return }
        try session.query(
            """
            UPDATE core_legacy_parents SET state = 'complete', status = ?, body = ?, body_expires_at = ?,
              completed_at = ?, request_body = NULL
            WHERE scope = ? AND request_id = ?
            """,
            [
                .integer(Int64(status)), CoreColumns.bytes(body),
                .integer(time + Int64(retentionDays) * 86_400_000), .integer(time), .text(context.scope),
                .text(context.requestID),
            ])
        if decision.isRefusal {
            try session.query(
                """
                INSERT INTO core_legacy_refusal_guards (scope, request_id, fingerprint, status, body, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(context.scope), .text(context.requestID), .text(context.fingerprint),
                    .integer(Int64(status)), CoreColumns.bytes(body), .integer(time),
                ])
        }
    }
}
