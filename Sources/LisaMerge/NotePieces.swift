// Note pieces (plan §8.3.1 "Concurrent note additions", §8.3.2): every note is its own piece, keyed by the operation
// that added it and at most one operation in size, so concurrent additions are all kept. `note.replaceObserved` (R1's
// notes text edit) adds its replacement and removes exactly the pieces it observed; a piece it didn't see stays. The
// display order is deterministic: committed pieces by commit position, then pending pieces by ID.

import LisaSyncProtocol

/// The note pieces of one item.
public struct NotePieces: Hashable, Sendable {
    public struct Piece: Hashable, Sendable {
        public let id: Identifier128
        public let text: String
        public fileprivate(set) var commit: CommitPosition?
    }

    private var pieces: [Identifier128: Piece] = [:]
    /// Replacements: what each one observed and so removes.
    private var removals: [Identifier128: ObservedCoverage] = [:]

    public init() {}

    /// Adds a note piece. Applying it again changes nothing.
    public mutating func add(id: Identifier128, text: String, commit: CommitPosition? = nil) {
        if var existing = pieces[id] {
            if existing.commit == nil, let commit { existing.commit = commit }
            pieces[id] = existing
            return
        }
        pieces[id] = Piece(id: id, text: text, commit: commit)
    }

    /// Adds the replacement `text`, when it has any, and removes the pieces `observed` covers. An empty replacement
    /// clears what it observed and adds nothing, as R1's `notes: ""` does (D-72).
    public mutating func replaceObserved(
        id: Identifier128, text: String, observed: ObservedCoverage, commit: CommitPosition? = nil
    ) {
        if !text.isEmpty { add(id: id, text: text, commit: commit) }
        removals[id] = observed
    }

    /// Records Core's commit position for a pending piece.
    public mutating func markCommitted(_ id: Identifier128, at commit: CommitPosition) {
        guard var piece = pieces[id], piece.commit == nil else { return }
        piece.commit = commit
        pieces[id] = piece
    }

    /// The pieces in effect, in display order.
    public var live: [Piece] {
        pieces.values.filter { piece in
            !removals.contains { remover, observed in
                remover != piece.id && observed.covers(piece.id, committedAt: piece.commit)
            }
        }.sorted { a, b in
            switch (a.commit, b.commit) {
            case (let x?, let y?) where x.position != y.position: return x.position < y.position
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.id.bytes.lexicographicallyPrecedes(b.id.bytes)
            }
        }
    }
}
