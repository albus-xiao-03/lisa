// How the controlled servers answer (plan §10.8 `Sources/LisaVerifyServers/`): normally, by accepting and then
// dropping the response, or with a rate limit; and whether their lookup by an action's identifiers is available.

/// The controlled servers' current behavior.
public struct ControlledBehavior: Sendable, Equatable {
    public enum Answer: String, Sendable, Equatable {
        /// Accept, count and answer.
        case normal
        /// Accept and count, then close the connection without any answer (S-24 variant iii).
        case acceptThenDrop = "accept-then-drop"
        /// Refuse with a rate limit; nothing is accepted or counted.
        case rateLimit = "rate-limit"
    }

    public var answer: Answer
    public var lookupEnabled: Bool

    public init(answer: Answer = .normal, lookupEnabled: Bool = true) {
        self.answer = answer
        self.lookupEnabled = lookupEnabled
    }
}
