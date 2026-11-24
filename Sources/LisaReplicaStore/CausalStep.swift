// What one causal step did (plan §8.2.2): each step is one short transaction, so a capture waits for at most one.

import LisaSyncProtocol

/// The outcome of one persisted causal step.
public enum CausalStep: Hashable, Sendable {
    /// An expansion step: the edges it read (at most 256) and the dependents it found ready.
    case expanded(edges: Int, enqueued: Int)
    /// A release step: the operations that entered the effective view (at most 256), in order.
    case released([Identifier128])
    /// Nothing is waiting to be expanded or released.
    case idle
}
