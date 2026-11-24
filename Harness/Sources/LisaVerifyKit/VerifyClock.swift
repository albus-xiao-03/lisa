// Wall-clock and monotonic readings (plan §10.8 "Timing"): wall-clock times are for correlation only; measurements use
// the monotonic clock on one device.

import Foundation

/// The harness's clocks.
public enum VerifyClock {
    /// UTC with milliseconds, for correlation.
    public static func wallClock(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Nanoseconds of the monotonic clock, for measurement on this host.
    public static func monotonicNanoseconds() -> UInt64 {
        UInt64(DispatchTime.now().uptimeNanoseconds)
    }
}
