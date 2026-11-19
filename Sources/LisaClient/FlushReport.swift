// The result of flushing the offline queue: what was applied, conflicted or failed, and why the flush stopped.

import Foundation

/// What one flush of the offline queue did.
public struct FlushReport: Hashable, Sendable {
    /// Why a flush stopped.
    public enum Stop: Hashable, Sendable {
        /// Every entry that could be sent now was sent.
        case finished
        /// Another flush was already running; it also sends the entries queued meanwhile.
        case alreadyRunning
        /// The host asked the client to wait: the next entry is not sent before this time.
        case deferred(until: Date)
        /// The flush could not go on and the remaining entries stay pending: the host could not be reached, the
        /// flush was cancelled or ran out of time, the device is not paired or was removed (401), or the host's API
        /// version is not supported.
        case stopped(ClientError)
        /// The queue could not be saved; the remaining entries stay pending.
        case storageFailure(String)
    }

    /// Entries the host applied, in order.
    public var applied: [String]
    /// Entries the host refused because their subject changed.
    public var conflicts: [String]
    /// Entries the host refused for another reason, or whose retry period ended.
    public var failed: [String]
    /// Why the flush stopped.
    public var stop: Stop
    /// How many entries still wait for the host afterwards.
    public var remaining: Int

    init(stop: Stop, remaining: Int) {
        applied = []
        conflicts = []
        failed = []
        self.stop = stop
        self.remaining = remaining
    }
}
