// A Core receipt as the replica records it (plan §8.2.1). The sync engine verifies Core's signature over the receipt
// before handing it here; the store keeps the exact signed bytes.

import LisaSyncProtocol

/// A verified receipt for one journal entry.
public struct ReplicaReceipt: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        /// Provisional: waiting for dependencies, no position.
        case waitingForDependencies = "waiting_for_dependencies"
        case accepted
        case acceptedWithConflict = "accepted_with_conflict"
        case rejected
    }

    public let operationID: Identifier128
    public let digest: Digest256
    public let status: Status
    /// The epoch and commit position of a final receipt; both `nil` on a provisional one.
    public let epochID: Identifier128?
    public let position: Int64?
    public let signedBytes: [UInt8]

    public init(
        operationID: Identifier128, digest: Digest256, status: Status, epochID: Identifier128?, position: Int64?,
        signedBytes: [UInt8]
    ) {
        self.operationID = operationID
        self.digest = digest
        self.status = status
        self.epochID = epochID
        self.position = position
        self.signedBytes = signedBytes
    }

    /// The journal state this receipt puts its entry in.
    public var state: ReplicaOperationState {
        switch status {
        case .waitingForDependencies: .waitingForDependencies
        case .accepted: .accepted
        case .acceptedWithConflict: .acceptedWithConflict
        case .rejected: .rejected
        }
    }
}
