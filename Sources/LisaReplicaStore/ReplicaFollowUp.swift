// Work a committed change leaves for later (plan §8.6.1 step 7): submitting a signed operation, signing a draft.

import LisaSyncProtocol

/// A follow-up recorded in the same transaction as the change that needs it.
public struct ReplicaFollowUp: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// Submit the journal entry to Core (§8.6.5 step 5).
        case submit
        /// Sign the draft once enrolled with a usable key (§8.6.2).
        case signDraft = "sign_draft"
    }

    public let kind: Kind
    public let operationID: Identifier128
    /// The generation of the change that recorded it.
    public let createdGeneration: Int64

    public init(kind: Kind, operationID: Identifier128, createdGeneration: Int64) {
        self.kind = kind
        self.operationID = operationID
        self.createdGeneration = createdGeneration
    }
}
