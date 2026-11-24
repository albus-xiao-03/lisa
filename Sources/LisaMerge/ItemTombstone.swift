// Deletion (plan §8.3.1 "Deletion versus stale or concurrent edits"): the tombstone dominates in any order; edits that
// arrive for a deleted item are recorded as superseded while retention allows; restoring creates a new identity, so a
// deleted item never comes back.

import LisaSyncProtocol

/// An item's deletion state.
public struct ItemTombstone: Hashable, Sendable {
    public private(set) var deletions: Set<Identifier128> = []
    public private(set) var superseded: Set<Identifier128> = []

    public init() {}

    public var isDeleted: Bool { !deletions.isEmpty }

    public mutating func delete(id: Identifier128) {
        deletions.insert(id)
    }

    /// Records an edit; returns whether it may apply (false: the item is deleted and the edit is kept as superseded).
    public mutating func admitEdit(id: Identifier128) -> Bool {
        guard isDeleted else { return true }
        superseded.insert(id)
        return false
    }
}
