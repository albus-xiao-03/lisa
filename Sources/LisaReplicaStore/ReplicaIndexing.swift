// The port that keeps the search index in the same transaction as the change (plan §7.2.3, §8.6.1 step 5, §8.6.3).
// Implemented by LisaLocalSearch.

import LisaSQLite

/// Updates the index when an item's effective view changes.
public protocol ReplicaIndexing: Sendable {
    /// Called inside the store's write transaction after `item` changed; reads what it needs through `session` and
    /// writes its index there. Throwing rolls the whole change back: nothing is saved without its index.
    func itemChanged(_ item: ReplicaItemKey, in session: SQLiteSession) throws
}
