// Where a case stands within a run (plan §10.8 "Repeatable and resumable").

/// A case's state in `run.json`.
public enum VerifyCaseState: String, Hashable, Sendable, Codable, CaseIterable {
    /// Selected, not started.
    case pending
    /// Started and not finished: a resume continues it, reconciling its actions first.
    case running
    /// Finished with a result recorded.
    case completed
    /// Waiting for the owner: a guided step, an observation or a device result to import.
    case waitingForOwner = "waiting-for-owner"
}
