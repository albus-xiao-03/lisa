// Input saved before it could be signed (plan §8.6.2): before enrollment, or while the signing key is unavailable. A
// draft keeps the operation ID it will be signed with, its original input and time.

import LisaSyncProtocol

/// A draft in the replica.
public struct ReplicaDraft: Hashable, Sendable {
    public enum Reason: String, Hashable, Sendable {
        /// "Saved on this device — not connected to your Lisa yet."
        case notEnrolled = "not_enrolled"
        /// "Saved on this device — can't be sent until this device is enrolled again."
        case keyUnavailable = "key_unavailable"
    }

    public enum State: String, Hashable, Sendable {
        case held
        /// Signed into the journal entry with the same operation ID.
        case signed
        /// Discarded by the owner, or retired by an authoritative deletion (§8.6.4, §8.6.7).
        case discarded
    }

    public let operationID: Identifier128
    public let command: LocalCommand
    /// Unix milliseconds of the original save; the signed operation's creation time.
    public let createdAt: Int64
    public let reason: Reason
    public let state: State

    public init(operationID: Identifier128, command: LocalCommand, createdAt: Int64, reason: Reason, state: State) {
        self.operationID = operationID
        self.command = command
        self.createdAt = createdAt
        self.reason = reason
        self.state = state
    }
}
