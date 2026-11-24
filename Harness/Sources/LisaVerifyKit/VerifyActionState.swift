// A logical action's state in the ledger (plan §10.8 "The action ledger", steps 1–4).

/// Where an action stands. Only `intent` and `submitting` are unresolved; resume observes and reconciles them and
/// never resends.
public enum VerifyActionState: String, Hashable, Sendable, Codable, CaseIterable {
    /// Recorded before any external I/O.
    case intent
    /// Recorded before the first byte: the provider may have it.
    case submitting
    /// The provider accepted it; its reference is recorded.
    case accepted
    /// The provider definitely refused it; nothing was accepted.
    case refused
    /// It reached `submitting`, and neither an outcome nor evidence was found.
    case ambiguous
    /// Ambiguous, and the owner authorized exactly one further attempt, recorded as `<action ID>.r2`.
    case superseded

    public var isUnresolved: Bool { self == .intent || self == .submitting }
}
