// One incarnation of this replica (plan §8.1.1): every launch that opens the replica starts one, with sequence numbers
// from 1; its first operation names the previous incarnation that created operations, and that one's last sequence.

import LisaSyncProtocol

/// An incarnation in the replica's chain, in launch order.
public struct IncarnationRecord: Hashable, Sendable {
    /// Launch order within this replica's file.
    public let ordinal: Int64
    public let incarnationID: Identifier128
    /// Unix milliseconds.
    public let startedAt: Int64
    /// The last sequence number used; 0 while it has created no operation.
    public let lastSequence: Int64
    /// What its first operation names; `nil` before that operation, or when no earlier incarnation created one.
    public let previous: IncarnationLink?

    public init(
        ordinal: Int64, incarnationID: Identifier128, startedAt: Int64, lastSequence: Int64, previous: IncarnationLink?
    ) {
        self.ordinal = ordinal
        self.incarnationID = incarnationID
        self.startedAt = startedAt
        self.lastSequence = lastSequence
        self.previous = previous
    }
}
