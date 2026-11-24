// A settable monotonic clock for tests and the deterministic demonstration (plan §7.2.3: "manual clock in tests"); never
// used for live operation. It only moves forward.

import Synchronization

/// A monotonic clock that moves only when told to.
public final class ManualMonotonicClock: MonotonicClock {
    private let current: Mutex<MonotonicInstant>

    public init(_ start: MonotonicInstant = MonotonicInstant(nanoseconds: 0)) {
        current = Mutex(start)
    }

    public func now() -> MonotonicInstant {
        current.withLock { $0 }
    }

    /// Moves the clock forward by `duration`; a negative duration is ignored, so the clock never goes back.
    public func advance(by duration: Duration) {
        guard duration > .zero else { return }
        current.withLock { $0 = $0.advanced(by: duration) }
    }
}
