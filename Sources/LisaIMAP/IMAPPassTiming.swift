// The time limits of one pass on the monotonic clock: the pass deadline from SyncLimits and the per-command timeout,
// converted to the wall-clock deadlines CurlIMAPSession compares against.

import Foundation

/// Which limit ended a wait.
enum IMAPTimeoutCause: Hashable, Sendable {
    case command
    case pass
}

/// Deadlines for one pass. Durations are measured on `ContinuousClock`, so wall-clock changes cannot stretch them.
struct IMAPPassTiming: Sendable {
    /// Waits that end within this much of a deadline count as having reached it, because CurlIMAPSession measures
    /// the same deadline on the wall clock.
    static let tolerance = Duration.milliseconds(100)
    let passSeconds: Int
    let commandSeconds: Int
    let passDeadline: ContinuousClock.Instant
    private let clock = ContinuousClock()

    init(passSeconds: Int, commandSeconds: Int) {
        self.passSeconds = max(1, passSeconds)
        self.commandSeconds = max(1, commandSeconds)
        passDeadline = clock.now.advanced(by: .seconds(self.passSeconds))
    }

    var now: ContinuousClock.Instant { clock.now }

    /// The command deadline counted from `start`, or the pass deadline when that comes first.
    func deadline(from start: ContinuousClock.Instant) -> (instant: ContinuousClock.Instant, cause: IMAPTimeoutCause) {
        let commandDeadline = start.advanced(by: .seconds(commandSeconds))
        return commandDeadline < passDeadline ? (commandDeadline, .command) : (passDeadline, .pass)
    }

    /// Whether `deadline` has been reached.
    func hasReached(_ deadline: ContinuousClock.Instant) -> Bool { now.advanced(by: Self.tolerance) >= deadline }

    /// `deadline` as a wall-clock date, for CurlIMAPSession's waits.
    func date(for deadline: ContinuousClock.Instant) -> Date {
        Date(timeIntervalSinceNow: max(0, Self.seconds(now.duration(to: deadline))))
    }

    /// The seconds left in the pass.
    var remainingPassSeconds: Double { max(0, Self.seconds(now.duration(to: passDeadline))) }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
