// What a change page did for one partition it lists (plan §8.4.2's four cases, and another epoch).

/// The outcome of a page for one listed partition.
public enum PartitionPageOutcome: Hashable, Sendable {
    /// The entries in `(cursor, to]` touching the partition were applied (row versions decide each), and the cursor
    /// moved to `to`.
    case applied(cursor: Int64, entries: Int)
    /// `to` is at or below the cursor: older than what the partition holds.
    case ignored(cursor: Int64)
    /// The partition is being repaired: the page is kept, verified but unapplied, until the repair publishes.
    case deferred
    /// The page starts after the cursor (or the partition has none and the page doesn't start at 0): refetch
    /// `(cursor, …]`; the cursor stays at its last proved value.
    case gap(cursor: Int64?)
    /// The page belongs to another epoch than the partition's; a new epoch is entered only through recovery (§8.5.2).
    case otherEpoch
}
