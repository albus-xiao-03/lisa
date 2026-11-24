// A logical action as a case's script plans it, before anything is recorded (plan §10.8 "The action ledger" step 1).

import Foundation
import LisaCrypto

/// One logical action at a fixed position in a case's script, so it keeps the same ID across resumes.
public struct VerifyPlannedAction: Hashable, Sendable, Codable {
    public let caseID: VerifyCaseID
    /// The action's position in the case's script, from 1.
    public let position: Int
    public let kind: VerifyActionKind
    /// The recipient, device or number as a per-run alias, never the address or number itself.
    public let targetAlias: String
    /// The operation ID Lisa (or the harness) submits; a resubmission reuses it, so Lisa deduplicates.
    public let operationID: String
    /// For a delivery, the slot `(occurrence, firing, recipient)` Lisa's journal follows (plan §8.10.6).
    public let slot: String?
    /// What the owner confirms, for example "brief email to recipient-1" or "model request, estimated $0.01".
    public let summary: String

    public init(
        caseID: VerifyCaseID, position: Int, kind: VerifyActionKind, targetAlias: String, operationID: String,
        slot: String?, summary: String
    ) {
        self.caseID = caseID
        self.position = position
        self.kind = kind
        self.targetAlias = targetAlias
        self.operationID = operationID
        self.slot = slot
        self.summary = summary
    }

    /// `OVA-<run-id>-<case>-<n>`.
    public func actionID(in run: VerifyRunID) -> String { "OVA-\(run.text)-\(caseID.text)-\(position)" }

    /// The digest a confirmation records: SHA-256 over the listed actions, one line each, sorted by action ID.
    public static func confirmationDigest(_ actions: [VerifyPlannedAction], in run: VerifyRunID) -> String {
        let lines = actions.map { action in
            [
                action.actionID(in: run), action.kind.rawValue, action.targetAlias, action.operationID,
                action.slot ?? "", action.summary,
            ].joined(separator: "\t")
        }.sorted()
        return Digests.sha256Hex(Data((run.text + "\n" + lines.joined(separator: "\n")).utf8))
    }
}
