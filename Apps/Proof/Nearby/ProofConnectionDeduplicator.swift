// PROOF ONLY — Apps/Proof never ships. Deduplication by device ID (plan §8.7 connection behavior): when two
// authenticated sessions join the same pair, the one opened by the lower device ID (bytewise) survives. Both devices
// apply the same rule, so both keep the same connection. A reconnection by the same opener replaces the older one.

import Foundation
import LisaSyncProtocol

struct ProofConnectionDeduplicator: Sendable {
    struct Session: Hashable, Sendable {
        let id: UUID
        let peer: Identifier128
        /// The device that opened the connection: the initiator.
        let openedBy: Identifier128
    }

    private(set) var live: [Identifier128: Session] = [:]

    /// Admits an authenticated session and returns the session that must close, if any.
    mutating func admit(_ session: Session) -> Session? {
        guard let existing = live[session.peer] else {
            live[session.peer] = session
            return nil
        }
        if session.openedBy == existing.openedBy || Self.precedes(session.openedBy, existing.openedBy) {
            live[session.peer] = session
            return existing
        }
        return session
    }

    mutating func remove(_ session: Session) {
        if live[session.peer] == session { live[session.peer] = nil }
    }

    static func precedes(_ lhs: Identifier128, _ rhs: Identifier128) -> Bool {
        lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }
}
