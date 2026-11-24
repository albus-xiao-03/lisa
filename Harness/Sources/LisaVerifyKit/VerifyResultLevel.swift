// Result levels for integrations and devices (plan §10.1), never merged.

/// How far a case's evidence reaches.
public enum VerifyResultLevel: String, Hashable, Sendable, Codable, CaseIterable, Comparable {
    /// The case exists, builds from a clean checkout, and its fixture mode passes (Claude).
    case harnessReady = "harness-ready"
    /// The production adapter passes against deterministic fixtures and controlled servers (Claude).
    case fixturePass = "fixture-pass"
    /// A real provider accepted the request in an owner-run case.
    case providerAccepted = "provider-accepted"
    /// The owner observed the required outcome end to end.
    case ownerVerified = "owner-verified"

    public static func < (lhs: VerifyResultLevel, rhs: VerifyResultLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
