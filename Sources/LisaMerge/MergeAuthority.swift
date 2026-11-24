// Who wrote a value (plan §8.3.1 "Owner correction versus a model or source value", §8.3.5, §8.14.2).

/// A value's authority. A model or source write never replaces an owner value — or one of ambiguous authority, which is
/// protected like an owner value — concurrent or later; an owner write replaces what it observed, whatever its
/// authority.
public enum MergeAuthority: String, Hashable, Sendable, CaseIterable {
    case owner
    case model
    case source
    /// A value whose authority a migration couldn't establish (§8.14.2).
    case ambiguous

    /// Protected values: only an owner write replaces them.
    public var isProtected: Bool { self == .owner || self == .ambiguous }

    /// Whether a write of this authority may replace an observed value of `other`'s authority.
    public func mayReplace(_ other: MergeAuthority) -> Bool { self == .owner || !other.isProtected }
}
