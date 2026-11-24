// One owner field as a multi-value register (plan §8.3.1): a write replaces only the versions it observed and its
// authority may replace; every unobserved candidate survives, and two or more surviving values of the winning
// authority class are a conflict. A model or source value that can't replace a protected one is kept as a suggestion.
// The state keeps every write's observed coverage, so a candidate arriving or committing later is judged the same way
// in any order; the display order is by candidate ID.

import LisaSyncProtocol

/// The merged state of one field.
public struct MultiValueRegister<Value: Hashable & Sendable>: Hashable, Sendable {
    /// One written value.
    public struct Candidate: Hashable, Sendable {
        public let id: Identifier128
        public let value: Value
        public let authority: MergeAuthority
        public var commit: CommitPosition?
        public let observed: ObservedCoverage
    }

    public private(set) var candidates: [Identifier128: Candidate] = [:]

    public init() {}

    /// Applies a write: its value becomes a candidate and it replaces what it observed. Applying it again changes
    /// nothing.
    public mutating func apply(
        id: Identifier128, value: Value, authority: MergeAuthority, observed: ObservedCoverage,
        commit: CommitPosition? = nil
    ) {
        if var existing = candidates[id] {
            if existing.commit == nil, let commit { existing.commit = commit }
            candidates[id] = existing
            return
        }
        candidates[id] = Candidate(id: id, value: value, authority: authority, commit: commit, observed: observed)
    }

    /// Records Core's commit position for a pending candidate.
    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        guard var candidate = candidates[id], candidate.commit == nil else { return }
        candidate.commit = commit
        candidates[id] = candidate
    }

    /// Whether `candidate` was replaced by another write that observed it and may replace its authority.
    public func isReplaced(_ candidate: Candidate) -> Bool {
        candidates.values.contains { writer in
            writer.id != candidate.id && writer.authority.mayReplace(candidate.authority)
                && writer.observed.covers(candidate.id, committedAt: candidate.commit)
        }
    }

    /// Surviving candidates in display order.
    public var live: [Candidate] {
        candidates.values.filter { !isReplaced($0) }.sorted { $0.id.bytes.lexicographicallyPrecedes($1.id.bytes) }
    }

    /// The field's values: the surviving protected ones if any, otherwise the surviving model and source ones.
    public var values: [Candidate] {
        let live = live
        let protected = live.filter { $0.authority.isProtected }
        return protected.isEmpty ? live : protected
    }

    /// Model and source values kept beside surviving protected values.
    public var suggestions: [Candidate] {
        let live = live
        return live.contains(where: { $0.authority.isProtected }) ? live.filter { !$0.authority.isProtected } : []
    }

    /// Two or more values: a conflict for the owner to resolve.
    public var isConflict: Bool { values.count > 1 }
}
