// The port that keeps the search index in the same transaction as the change (plan §7.2.3, §8.6.1 step 5, §8.6.3).
// Implemented by LisaLocalSearch.

import LisaSQLite

/// Updates the index when an item's effective view changes.
public protocol ReplicaIndexing: Sendable {
    /// Called inside the store's write transaction after `item` changed; reads what it needs through `session` and
    /// writes its index there. Throwing rolls the whole change back: nothing is saved without its index.
    func itemChanged(_ item: ReplicaItemKey, in session: SQLiteSession) throws

    /// Writes `item`'s entries for a staged installation into `table` (`staged_search_postings`), from the staged
    /// effective view's searchable text (plan §8.6.3); the staged index is swapped in with the canonical tables.
    func stage(_ item: ReplicaItemKey, searchableText: [String], into table: String, in session: SQLiteSession) throws
}

extension ReplicaIndexing {
    /// An index without a staged form stages nothing.
    public func stage(_ item: ReplicaItemKey, searchableText: [String], into table: String, in session: SQLiteSession)
        throws
    {}
}
