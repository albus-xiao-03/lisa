// How a staged full-snapshot installation ended at its installation point (plan §8.6.3). The backlog is evaluated
// before anything is applied: an invalidated staging applied nothing, and a fresher cut is fetched.

/// The outcome of the installation point.
public enum SnapshotInstallationOutcome: Hashable, Sendable {
    public enum Invalidation: Hashable, Sendable {
        /// More than 2,048 local changes after the last applied generation.
        case backlogTooLarge(Int)
        /// A canonical page beyond the cut was installed after staging began (or the cut is older than a cursor).
        case newerCanonicalPage
        /// A covered partition's cursor is in another epoch.
        case epochChanged
        /// The replica covers a partition the snapshot doesn't.
        case coverageChanged
    }

    /// Swapped in: canonical tables, staged view and staged index together, with cursors at the cut.
    case installed(generation: Int64)
    /// Discarded without applying anything.
    case invalidated(Invalidation)
    /// Not every chunk of the signed manifest has been staged and verified.
    case incomplete(missingChunks: Int)
}
