// An instant on the boot-time clock (plan §7.2.3, §8.6.1, §8.11.4): nanoseconds since the system booted, counting time
// asleep and time a process was stopped, shared by every process on the host, and unaffected by wall-clock steps.
// Timeouts, backoff and freshness use it; it is never shown or stored as a date.

/// A point on the boot-time clock.
public struct MonotonicInstant: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Nanoseconds since boot.
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static func < (lhs: MonotonicInstant, rhs: MonotonicInstant) -> Bool { lhs.nanoseconds < rhs.nanoseconds }

    /// The time from `earlier` to this instant; zero if `earlier` is later.
    public func duration(since earlier: MonotonicInstant) -> Duration {
        guard nanoseconds >= earlier.nanoseconds else { return .zero }
        return .nanoseconds(Int64(clamping: nanoseconds - earlier.nanoseconds))
    }

    /// This instant moved by `duration`, saturating: never below boot, never past the largest instant.
    public func advanced(by duration: Duration) -> MonotonicInstant {
        let (seconds, attoseconds) = duration.components
        let scaled = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let total = scaled.partialValue.addingReportingOverflow(attoseconds / 1_000_000_000)
        guard !scaled.overflow, !total.overflow else {
            return MonotonicInstant(nanoseconds: seconds < 0 ? 0 : .max)
        }
        let delta = total.partialValue
        if delta >= 0 {
            let (sum, overflow) = nanoseconds.addingReportingOverflow(UInt64(delta))
            return MonotonicInstant(nanoseconds: overflow ? .max : sum)
        }
        let magnitude = delta.magnitude
        return MonotonicInstant(nanoseconds: nanoseconds > magnitude ? nanoseconds - magnitude : 0)
    }

    public var description: String { "boot+\(nanoseconds)ns" }
}
