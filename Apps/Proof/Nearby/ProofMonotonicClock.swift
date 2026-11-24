// PROOF ONLY — Apps/Proof never ships. The one clock the proof measures with (plan §10.8 timing): this device's
// monotonic uptime in nanoseconds. Wall-clock times are recorded for correlation only, never for a measurement.

import Dispatch

enum ProofMonotonicClock {
    static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
