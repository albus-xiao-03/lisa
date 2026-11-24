// PROOF ONLY — Apps/Proof never ships. A thread-safe "first caller wins" flag, so a continuation fed by a callback
// that may fire more than once (path updates, connection states, DNS replies, timeouts) resumes exactly once.

import Foundation

final class ProbeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// True for the first call only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
