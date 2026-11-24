// The injected source of monotonic time (plan §7.2.3 `MonotonicClock`): `BootTimeClock` in production, a manual clock in
// tests. Timeouts, backoff and freshness read it; nothing that depends on elapsed time reads the wall clock.

/// Supplies the current instant on the boot-time clock.
public protocol MonotonicClock: Sendable {
    func now() -> MonotonicInstant
}
