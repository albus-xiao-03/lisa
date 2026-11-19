// Test-only controlled substitute (plan §10) at the client's QueueStorage boundary: the real file storage, until the
// test "crashes" the app, after which nothing more reaches the file, as when the process is killed while a request is
// in flight. Used by the offline synchronization suite (L21) and later client suites.

import Foundation
import LisaClient
import Synchronization

/// A queue storage that forwards to `base` until ``crash()``; afterwards every save fails and the file keeps what the
/// app had saved before it stopped.
final class CrashableQueueStorage: QueueStorage {
    /// The failure every save gets after the crash.
    struct Crashed: Error, CustomStringConvertible {
        var description: String { "the synthetic app process has stopped" }
    }

    private let base: any QueueStorage
    private let crashed = Mutex(false)

    init(base: any QueueStorage) {
        self.base = base
    }

    /// Stops the synthetic process: nothing it does from now on reaches the storage.
    func crash() {
        crashed.withLock { $0 = true }
    }

    func load() throws -> [QueuedRequest] {
        try base.load()
    }

    func save(_ entries: [QueuedRequest]) throws {
        guard !crashed.withLock({ $0 }) else { throw Crashed() }
        try base.save(entries)
    }
}
