// The production monotonic clock (plan §7.2.3, §8.11.4): `CLOCK_BOOTTIME` on Linux, which counts suspend and is what
// Core's `health.json` publishes as `bootTimeNanos`; on Apple platforms `CLOCK_MONOTONIC`, which keeps counting while
// the system sleeps (the continuous clock).

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Reads the boot-time clock.
public struct BootTimeClock: MonotonicClock {
    public init() {}

    public func now() -> MonotonicInstant {
        #if canImport(Glibc)
            var time = timespec()
            clock_gettime(CLOCK_BOOTTIME, &time)
            return MonotonicInstant(nanoseconds: UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec))
        #else
            return MonotonicInstant(nanoseconds: clock_gettime_nsec_np(CLOCK_MONOTONIC))
        #endif
    }
}
