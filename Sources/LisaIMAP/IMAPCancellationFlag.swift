// Cancellation shared between the task that asked for a pass and the thread that runs it.

import Synchronization

/// Set when the calling task is cancelled; the pass thread checks it while it waits for the server.
final class IMAPCancellationFlag: Sendable {
    private let flag = Atomic<Bool>(false)

    init() {}

    func cancel() { flag.store(true, ordering: .relaxed) }

    var isCancelled: Bool { flag.load(ordering: .relaxed) }
}
