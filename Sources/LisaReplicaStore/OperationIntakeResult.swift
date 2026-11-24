// What happened to an arriving operation under the duplicate rules, which hold on every replica with no exception
// (plan §8.2.1, R2-SYNC-02).

import LisaSyncProtocol

/// The outcome of receiving a verified operation.
public enum OperationIntakeResult: Hashable, Sendable {
    /// New: stored in the journal at this generation.
    case stored(generation: Int64)
    /// Same ID and digest as a stored entry, whose state is given.
    case duplicate(state: ReplicaOperationState)
    /// Same ID, another digest: refused, and a security event recorded.
    case rejectedIdentityReuse
    /// The same `(device, incarnation, sequence)` under another ID: refused, and a security event recorded.
    case rejectedSequenceReuse
}
