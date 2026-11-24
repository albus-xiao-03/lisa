// PROOF ONLY — Apps/Proof never ships. The four-timestamp offset estimate of plan §10.8: 20 exchanges over the
// session, the minimum-delay sample kept. It is used only to report one-way events, never as a measurement.

struct ProofClockSample: Codable, Sendable, Equatable {
    /// t1: request sent (this device); t2: received and t3: replied (peer); t4: reply received (this device).
    let t1: UInt64, t2: UInt64, t3: UInt64, t4: UInt64

    /// Round-trip delay without the peer's processing time, in nanoseconds.
    var delay: Int64 { Int64(bitPattern: t4 &- t1) - Int64(bitPattern: t3 &- t2) }
    /// Peer clock minus this clock, in nanoseconds.
    var offset: Int64 {
        (Int64(bitPattern: t2 &- t1) + Int64(bitPattern: t3 &- t4)) / 2
    }
}

enum ProofClockOffset {
    static let exchanges = 20

    /// The minimum-delay sample's offset and delay, or nil without samples.
    static func estimate(_ samples: [ProofClockSample]) -> (offsetNanoseconds: Int64, delayNanoseconds: Int64)? {
        guard let best = samples.min(by: { $0.delay < $1.delay }) else { return nil }
        return (best.offset, best.delay)
    }
}
