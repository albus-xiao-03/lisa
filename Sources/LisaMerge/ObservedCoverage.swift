// What an operation's observed set covers (plan §8.3.2): every committed piece of the item and field with a commit
// position at or below the horizon, in the horizon's epoch and partition, plus the explicitly listed pieces. Anything
// else — a later arrival, a pending piece not listed — is not covered and stays.

import LisaSyncProtocol

/// The evaluable part of an `ObservedSet`.
public struct ObservedCoverage: Hashable, Sendable {
    public let horizon: ObservedHorizon?
    public let pieces: Set<Identifier128>

    public init(horizon: ObservedHorizon?, pieces: Set<Identifier128>) {
        self.horizon = horizon
        self.pieces = pieces
    }

    public init(_ observed: ObservedSet) {
        self.init(horizon: observed.horizon, pieces: Set(observed.pieces))
    }

    /// Nothing observed.
    public static let nothing = ObservedCoverage(horizon: nil, pieces: [])

    /// Whether the piece `id`, committed at `commit` (or pending), was observed.
    public func covers(_ id: Identifier128, committedAt commit: CommitPosition?) -> Bool {
        if pieces.contains(id) { return true }
        guard let horizon, let commit else { return false }
        return commit.epochID == horizon.epochID && commit.partition == horizon.partition
            && commit.position <= horizon.position
    }
}
