// Runs blocking libcurl work on its own thread, so it never occupies a thread of Swift's cooperative pool.

import Foundation

/// Runs blocking work on a dedicated thread.
public enum CurlWorkerThread {
    /// Runs `body` on a new thread and returns its result. Cancelling the calling task calls `onCancel`, which must
    /// make `body` return promptly.
    public static func run<T: Sendable>(
        name: String, onCancel: @escaping @Sendable () -> Void = {}, _ body: @escaping @Sendable () -> T
    ) async -> T {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                let thread = Thread { continuation.resume(returning: body()) }
                thread.name = name
                thread.start()
            }
        } onCancel: {
            onCancel()
        }
    }
}
