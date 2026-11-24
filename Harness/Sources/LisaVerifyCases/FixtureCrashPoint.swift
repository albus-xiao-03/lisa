// Where a fixture process is killed for S-24's interruption variants (plan §10.8 acceptance): a real SIGKILL to the
// process itself, so nothing after that point runs — no buffered write, no cleanup.

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// A named point at which the harness process kills itself.
public enum FixtureCrashPoint: String, Sendable, CaseIterable {
    /// After the intent is committed, before any I/O (variant i).
    case afterIntent = "after-intent"
    /// After the server accepted and answered, before the harness recorded it (variant ii).
    case afterAccept = "after-accept"

    /// Kills this process with SIGKILL.
    public func strike() -> Never {
        kill(getpid(), SIGKILL)
        while true { pause() }
    }
}
