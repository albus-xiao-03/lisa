// A small pool of idle easy handles, so connections are reused between exchanges without ever sharing a handle.

import Synchronization

/// Idle handles. A handle is taken for one exchange and returned afterwards; at most `capacity` are kept.
final class CurlHandlePool: Sendable {
    private let idle = Mutex<[CurlEasy]>([])
    let capacity: Int

    init(capacity: Int) { self.capacity = max(0, capacity) }

    func take() throws(CurlSetupError) -> CurlEasy {
        if let handle = idle.withLock({ $0.popLast() }) {
            handle.reset()
            return handle
        }
        return try CurlEasy()
    }

    /// Returns a handle for reuse. It is reset first, so no callback can reach the finished exchange's freed state;
    /// a handle whose exchange failed is then dropped, which closes its connections.
    func give(back handle: CurlEasy, reusable: Bool) {
        handle.reset()
        guard reusable else {
            handle.cleanup()
            return
        }
        idle.withLock { handles in
            if handles.count < capacity { handles.append(handle) }
        }
    }
}
