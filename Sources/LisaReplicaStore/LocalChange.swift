// One entry of the local change journal (plan §8.6.3): `(generation, kind, references)`. Staging reads the complete,
// ordered sequence of changes after any generation from these.

import LisaSyncProtocol

/// A change that advanced the local state generation.
public struct LocalChange: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case journalEntry = "journal_entry"
        case draftChange = "draft_change"
        case receipt
        case rejection
        case revocation
        case canonicalPage = "canonical_page"
        case coverage
        case conflictResolution = "conflict_resolution"
    }

    public let generation: Int64
    public let kind: Kind
    /// The operations (or drafts, by their operation IDs) the change is about.
    public let operations: [Identifier128]
    /// The items whose effective view it may change.
    public let items: [ReplicaItemKey]

    public init(generation: Int64, kind: Kind, operations: [Identifier128], items: [ReplicaItemKey]) {
        self.generation = generation
        self.kind = kind
        self.operations = operations
        self.items = items
    }
}
