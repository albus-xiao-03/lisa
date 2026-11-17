// Conversion from Swift's `Duration`, used in the public settings, to NIO's `TimeAmount`.

import NIOCore

extension TimeAmount {
    /// The same span, to the nanosecond.
    init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        self = .nanoseconds(seconds * 1_000_000_000 + attoseconds / 1_000_000_000)
    }
}
