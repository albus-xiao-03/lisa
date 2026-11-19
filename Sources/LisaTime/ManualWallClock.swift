// A settable clock for the deterministic demonstration and for verification; never used for live operation.

import Foundation
import Synchronization

/// A clock whose instant changes only when told to, so that demonstration output is reproducible.
public final class ManualWallClock: WallClock {
    private let current: Mutex<Date>

    public init(_ start: Date) {
        current = Mutex(start.roundedToMilliseconds)
    }

    public func now() -> Date {
        current.withLock { $0 }
    }

    /// Moves the clock to `instant`.
    public func set(_ instant: Date) {
        current.withLock { $0 = instant.roundedToMilliseconds }
    }

    /// Moves the clock forward by `seconds`.
    public func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds).roundedToMilliseconds }
    }
}
