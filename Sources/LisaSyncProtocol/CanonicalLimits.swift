// Size and nesting limits for canonical JSON (plan §8.16.1, §8.16.2).

/// The bounds a canonical encoding or decoding is checked against.
public struct CanonicalLimits: Hashable, Sendable {
    /// The deepest nesting of arrays and objects any canonical value may have (plan §8.16.1).
    public static let maximumNestingDepth = 16

    /// The largest encoding accepted, in bytes.
    public var maxBytes: Int
    /// The deepest container nesting accepted; a top-level object or array is at depth 1.
    public var maxDepth: Int

    /// - Precondition: `maxBytes` is positive and `maxDepth` is between 1 and `maximumNestingDepth`.
    public init(maxBytes: Int, maxDepth: Int = CanonicalLimits.maximumNestingDepth) {
        precondition(maxBytes > 0, "a canonical size limit must be positive")
        precondition((1...CanonicalLimits.maximumNestingDepth).contains(maxDepth), "nesting is at most 16")
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
    }

    /// One canonical operation body, metadata included: 64 KiB (plan §8.16.2).
    public static let operationBody = CanonicalLimits(maxBytes: TransferBudgets.operationBodyBytes)
}
