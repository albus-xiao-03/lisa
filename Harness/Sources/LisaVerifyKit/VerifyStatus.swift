// R2's statuses (plan §10.1), used unchanged in every result.

/// A check's status. Every result also names its executor and its exact cause.
public enum VerifyStatus: String, Hashable, Sendable, Codable, CaseIterable {
    case pass = "PASS"
    case fail = "FAIL"
    case notRunEnvironment = "NOT_RUN_ENVIRONMENT"
    case notRunCredentials = "NOT_RUN_CREDENTIALS"
    case blockedPermission = "BLOCKED_PERMISSION"
    case outOfScope = "OUT_OF_SCOPE"
}
