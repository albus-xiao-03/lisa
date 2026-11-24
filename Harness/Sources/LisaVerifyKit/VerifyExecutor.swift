// Who runs a check (plan §10.1): Claude never runs a check that needs an owner account, device or live action.

/// A check's executor.
public enum VerifyExecutor: String, Hashable, Sendable, Codable, CaseIterable {
    case claude
    case owner
}
