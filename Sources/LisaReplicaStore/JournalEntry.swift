// One operation in the replica's journal (plan §8.6.1): its exact signed bytes, where it came from, where it stands
// with Core, and whether it is still an overlay in the effective view.

import LisaSyncProtocol

/// A journal entry.
public struct JournalEntry: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable {
        /// Created here.
        case local
        /// Received from a peer or Core.
        case relayed
    }

    public let operation: SignedOperation
    public let operationID: Identifier128
    public let digest: Digest256
    /// `nil` for Core's legacy translation.
    public let origin: OriginTriple?
    public let item: ReplicaItemKey
    public let operationType: String
    public let source: Source
    public let state: ReplicaOperationState
    /// Still shown on top of canonical state: it leaves only when canonical state containing it is installed, or
    /// when it is rejected or revoked (§8.6.1, §8.6.4) — never when a receipt arrives.
    public let isOverlay: Bool
    /// The receipt's exact signed bytes, once one arrived.
    public let receipt: [UInt8]?
    /// The epoch and position of its final receipt.
    public let commitEpoch: Identifier128?
    public let commitPosition: Int64?
    /// The local state generation that stored it.
    public let storedGeneration: Int64
    /// Whether it was signed from a draft.
    public let fromDraft: Bool

    public init(
        operation: SignedOperation, operationID: Identifier128, digest: Digest256, origin: OriginTriple?,
        item: ReplicaItemKey, operationType: String, source: Source, state: ReplicaOperationState, isOverlay: Bool,
        receipt: [UInt8]?, commitEpoch: Identifier128?, commitPosition: Int64?, storedGeneration: Int64,
        fromDraft: Bool
    ) {
        self.operation = operation
        self.operationID = operationID
        self.digest = digest
        self.origin = origin
        self.item = item
        self.operationType = operationType
        self.source = source
        self.state = state
        self.isOverlay = isOverlay
        self.receipt = receipt
        self.commitEpoch = commitEpoch
        self.commitPosition = commitPosition
        self.storedGeneration = storedGeneration
        self.fromDraft = fromDraft
    }
}
