// PROOF ONLY — Apps/Proof never ships. Per-endpoint backoff on the monotonic clock after a handshake or
// authentication failure (plan §8.7 "After a failure or retry"): 1 s doubling to 30 s, cleared by a success or a
// roster change. There is never an unauthenticated fallback.

struct ProofEndpointBackoff: Sendable {
    static let initialNanoseconds: UInt64 = 1_000_000_000
    static let maximumNanoseconds: UInt64 = 30_000_000_000

    private var state: [String: (delay: UInt64, notBefore: UInt64)] = [:]

    func mayAttempt(_ endpoint: String, now: UInt64 = ProofMonotonicClock.nowNanoseconds()) -> Bool {
        guard let entry = state[endpoint] else { return true }
        return now >= entry.notBefore
    }

    mutating func recordFailure(_ endpoint: String, now: UInt64 = ProofMonotonicClock.nowNanoseconds()) {
        let delay = state[endpoint].map { min($0.delay * 2, Self.maximumNanoseconds) } ?? Self.initialNanoseconds
        state[endpoint] = (delay, now + delay)
    }

    mutating func recordSuccess(_ endpoint: String) {
        state[endpoint] = nil
    }

    mutating func rosterChanged() {
        state.removeAll()
    }
}
