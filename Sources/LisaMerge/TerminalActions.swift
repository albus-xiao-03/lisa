// An item's status as a set of terminal actions with explicit reopen references (plan §8.3.1): completion and
// cancellation are recorded separately from other edits; concurrent completion and cancellation are both kept
// ("completed and cancelled", for review); a reopen names the terminal actions it reopens, and one it didn't see stays
// in effect. A reopen that names none reopens those its observed coverage covers, by ID or by commit position under
// its horizon (a v1 reopen observed at a projection revision, docs/DECISIONS.md D-72).

import LisaSyncProtocol

/// The merged status of an item.
public struct TerminalActions: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case completed
        case cancelled
    }

    public enum Status: String, Hashable, Sendable {
        case open
        case completed
        case cancelled
        /// Both in effect: terminal, shown for review; reminders and deliveries are suppressed.
        case completedAndCancelled = "completed-and-cancelled"

        public var isTerminal: Bool { self != .open }
    }

    private var actions: [Identifier128: Kind] = [:]
    private var commits: [Identifier128: CommitPosition] = [:]
    private var reopened: Set<Identifier128> = []
    /// Reopens that name nothing, each with the coverage it reopens.
    private var coveringReopens: [Identifier128: ObservedCoverage] = [:]

    public init() {}

    /// A terminal action, with Core's commit position when known.
    public mutating func record(_ kind: Kind, id: Identifier128, commit: CommitPosition? = nil) {
        if actions[id] == nil { actions[id] = kind }
        if commits[id] == nil, let commit { commits[id] = commit }
    }

    /// Records Core's commit position for a terminal action applied while pending.
    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        if actions[id] != nil, commits[id] == nil { commits[id] = commit }
    }

    /// A reopen of exactly the terminal actions it names.
    public mutating func reopen(naming targets: Set<Identifier128>) {
        reopened.formUnion(targets)
    }

    /// A reopen that names nothing: it reopens exactly the terminal actions `observed` covers. One it didn't see,
    /// committed after its horizon or still pending, stays in effect.
    public mutating func reopen(id: Identifier128, covering observed: ObservedCoverage) {
        coveringReopens[id] = observed
    }

    /// The terminal actions still in effect.
    public var inEffect: [Identifier128: Kind] {
        actions.filter { action in
            !reopened.contains(action.key)
                && !coveringReopens.values.contains { $0.covers(action.key, committedAt: commits[action.key]) }
        }
    }

    public var status: Status {
        let kinds = Set(inEffect.values)
        switch (kinds.contains(.completed), kinds.contains(.cancelled)) {
        case (true, true): return .completedAndCancelled
        case (true, false): return .completed
        case (false, true): return .cancelled
        case (false, false): return .open
        }
    }
}
