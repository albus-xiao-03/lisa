// A security event the duplicate rules raised on this replica (plan §8.2.1): identity reuse or sequence reuse, kept
// with both digests.

import LisaSyncProtocol

/// A recorded security event.
public struct ReplicaSecurityEvent: Hashable, Sendable {
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
