// The injected source of the current instant; time-dependent logic never reads the wall clock directly.

import Foundation

/// Supplies the current instant. Production code uses ``SystemWallClock``; the demonstration uses ``ManualWallClock``.
public protocol WallClock: Sendable {
    /// The current instant, rounded to whole milliseconds so that it survives persistence unchanged.
    func now() -> Date
}

/// Reads the operating-system clock.
public struct SystemWallClock: WallClock {
    public init() {}

    public func now() -> Date {
        Date().roundedToMilliseconds
    }
}
