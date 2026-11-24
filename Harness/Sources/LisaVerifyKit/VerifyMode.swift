// The harness's modes (plan §10.8 "Modes").

/// How a case runs.
public enum VerifyMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// Deterministic fixtures and controlled servers; no account; the default.
    case fixture
    /// Owner-invoked: Apple builds on physical devices, signed and provisioned by the owner.
    case device
    /// Owner-invoked: real providers under the owner's identity, every logical action confirmed first.
    case live
}
