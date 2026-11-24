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
}
