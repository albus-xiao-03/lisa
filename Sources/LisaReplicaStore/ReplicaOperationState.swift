// Where a journal entry stands with Core (plan §8.6.1, §8.2.1). Peer custody is kept apart, in custody
// acknowledgements, and never changes this state (R2-SYNC-04).

/// The Core-side state of one operation in the journal.
public enum ReplicaOperationState: String, Hashable, Sendable, CaseIterable {
    /// Committed in this replica only: "Saved on this device".
    case pending
    /// Sent to Core, no receipt yet.
    case submitted
    /// Core holds it until its dependencies are decided (a provisional receipt, no position).
    case waitingForDependencies = "waiting_for_dependencies"
    /// A final receipt: "Synced with Core".
    case accepted
    /// A final receipt with a conflict to review.
    case acceptedWithConflict = "accepted_with_conflict"
    /// A final receipt refusing it; it leaves the effective view and stays in the journal.
    case rejected

    /// Whether a final receipt decided it.
    public var isFinal: Bool { self == .accepted || self == .acceptedWithConflict || self == .rejected }
}
