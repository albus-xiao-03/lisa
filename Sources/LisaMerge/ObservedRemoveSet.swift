// Tags as an observed-remove set (plan §8.3.1 "Concurrent tag additions and removals"): each addition is its own piece;
// a removal covers only the additions it observed, so a concurrent addition of the same element survives it.

import LisaSyncProtocol

/// The merged state of a set field.
public struct ObservedRemoveSet<Element: Hashable & Sendable>: Hashable, Sendable {
    struct Addition: Hashable, Sendable {
        let element: Element
        var commit: CommitPosition?
    }

    private var additions: [Identifier128: Addition] = [:]
    private var removals: [Identifier128: ObservedCoverage] = [:]

    public init() {}

    public mutating func add(_ element: Element, id: Identifier128, commit: CommitPosition? = nil) {
        if var existing = additions[id] {
            if existing.commit == nil { existing.commit = commit }
            additions[id] = existing
        } else {
            additions[id] = Addition(element: element, commit: commit)
        }
    }

    /// A removal of whatever additions `observed` covers.
    public mutating func remove(id: Identifier128, observed: ObservedCoverage) {
        removals[id] = observed
    }

    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        guard var addition = additions[id], addition.commit == nil else { return }
        addition.commit = commit
        additions[id] = addition
    }

    /// The elements with at least one addition no removal covers.
    public var elements: Set<Element> {
        Set(
            additions.filter { id, addition in
                !removals.values.contains { $0.covers(id, committedAt: addition.commit) }
            }.map(\.value.element))
    }
}
