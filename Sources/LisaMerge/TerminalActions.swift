// An item's status as a set of terminal actions with explicit reopen references (plan §8.3.1): completion and
// cancellation are recorded separately from other edits; concurrent completion and cancellation are both kept
// ("completed and cancelled", for review); a reopen names the terminal actions it reopens, and one it didn't see stays
// in effect.

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
    private var reopened: Set<Identifier128> = []

    public init() {}

    public mutating func record(_ kind: Kind, id: Identifier128) {
        if actions[id] == nil { actions[id] = kind }
    }

    /// A reopen of exactly the terminal actions it names.
    public mutating func reopen(naming targets: Set<Identifier128>) {
        reopened.formUnion(targets)
    }

    /// The terminal actions still in effect.
    public var inEffect: [Identifier128: Kind] { actions.filter { !reopened.contains($0.key) } }

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
