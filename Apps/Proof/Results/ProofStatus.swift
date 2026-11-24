// PROOF ONLY — Apps/Proof never ships. R2's statuses (plan §10.1), used unchanged in every evidence entry and result.

enum ProofStatus: String, Codable, Sendable {
    case pass = "PASS"
    case fail = "FAIL"
    case notRunEnvironment = "NOT_RUN_ENVIRONMENT"
    case notRunCredentials = "NOT_RUN_CREDENTIALS"
    case blockedPermission = "BLOCKED_PERMISSION"
    case outOfScope = "OUT_OF_SCOPE"
}
