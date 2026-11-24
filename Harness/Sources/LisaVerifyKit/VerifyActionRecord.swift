// A logical action as the ledger holds it (plan §10.8 "The action ledger").

/// One ledger row: the planned action's identities, the confirmation that covers it, its state and outcome.
public struct VerifyActionRecord: Hashable, Sendable, Codable {
    public let actionID: String
    public let runID: VerifyRunID
    public let caseID: VerifyCaseID
    public let position: Int
    public let kind: VerifyActionKind
    public let targetAlias: String
    public let operationID: String
    public let slot: String?
    public let confirmationDigest: String
    /// The ambiguous action this one retries (`<id>.r2`), if any.
    public let retryOf: String?
    public let state: VerifyActionState
    /// The provider's reference (`Message-ID`, `apns-id`, call SID, model request ID); local only, exported as a
    /// digest.
    public let providerReference: String?
    public let outcome: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
        actionID: String, runID: VerifyRunID, caseID: VerifyCaseID, position: Int, kind: VerifyActionKind,
        targetAlias: String, operationID: String, slot: String?, confirmationDigest: String, retryOf: String?,
        state: VerifyActionState, providerReference: String?, outcome: String?, createdAt: String, updatedAt: String
    ) {
        self.actionID = actionID
        self.runID = runID
        self.caseID = caseID
        self.position = position
        self.kind = kind
        self.targetAlias = targetAlias
        self.operationID = operationID
        self.slot = slot
        self.confirmationDigest = confirmationDigest
        self.retryOf = retryOf
        self.state = state
        self.providerReference = providerReference
        self.outcome = outcome
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
