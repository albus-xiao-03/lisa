// Test-only controlled substitute for the host's daily model-request budget (MODEL-01, OPS-02): it grants a fixed
// number of reservations or fails every one, and records each attempt. Used by L14 and L22.

import LisaInference
import Synchronization

/// A scripted request budget.
final class ScriptedRequestBudget: ModelRequestBudget {
    /// How reservations are answered.
    enum Behavior: Sendable {
        /// Grant this many reservations, then refuse.
        case grant(Int)
        /// Throw on every reservation, as when the count cannot be recorded.
        case fail
    }

    /// The error thrown by a failing budget.
    struct RecordingFailure: Error {}

    private struct State {
        var behavior: Behavior
        var attempts = 0
        var limits: [Int] = []
    }

    private let state: Mutex<State>

    init(_ behavior: Behavior) {
        state = Mutex(State(behavior: behavior))
    }

    func reserve(limit: Int) throws -> Bool {
        try state.withLock { state in
            state.attempts += 1
            state.limits.append(limit)
            switch state.behavior {
            case .fail:
                throw RecordingFailure()
            case .grant(let remaining):
                guard remaining > 0 else { return false }
                state.behavior = .grant(remaining - 1)
                return true
            }
        }
    }

    /// How many reservations were attempted.
    var attempts: Int {
        state.withLock { $0.attempts }
    }

    /// The daily limit passed with each attempt.
    var limitsSeen: [Int] {
        state.withLock { $0.limits }
    }
}
