// A device revocation as the replica records it (plan §8.1.3): learned from a verified roster, with the epoch and
// position at which it happened. Revocations are permanent, so the replica keeps the union of every one it learned.

import LisaSyncProtocol

/// One recorded revocation.
public struct ReplicaRevocation: Hashable, Sendable {
    public let deviceID: Identifier128
    public let epochID: Identifier128
    public let position: Int64
    /// When this replica learned it, in Unix milliseconds, and the local state generation that recorded it.
    public let learnedAt: Int64
    public let learnedGeneration: Int64

    public init(
        deviceID: Identifier128, epochID: Identifier128, position: Int64, learnedAt: Int64, learnedGeneration: Int64
    ) {
        self.deviceID = deviceID
        self.epochID = epochID
        self.position = position
        self.learnedAt = learnedAt
        self.learnedGeneration = learnedGeneration
    }
}
