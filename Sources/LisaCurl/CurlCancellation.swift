// Cancellation shared between a Swift task and the thread blocked in libcurl, checked from libcurl's progress
// callback.

import CCurlShim
import Synchronization

/// Set when the calling task is cancelled; libcurl aborts the transfer at its next progress callback.
final class CurlCancellation: Sendable {
    private let flag = Atomic<Bool>(false)
    /// The C binding handed to libcurl; valid for this object's lifetime. It is written once, in init.
    nonisolated(unsafe) let binding: UnsafeMutablePointer<lisa_curl_abort_binding>

    init() {
        binding = UnsafeMutablePointer<lisa_curl_abort_binding>.allocate(capacity: 1)
        binding.initialize(to: lisa_curl_abort_binding(check: curlAbortCheck, userdata: nil))
        binding.pointee.userdata = Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        binding.deinitialize(count: 1)
        binding.deallocate()
    }

    func cancel() { flag.store(true, ordering: .relaxed) }

    var isCancelled: Bool { flag.load(ordering: .relaxed) }
}

private func curlAbortCheck(_ userdata: UnsafeMutableRawPointer?) -> Int32 {
    guard let userdata else { return 1 }
    return Unmanaged<CurlCancellation>.fromOpaque(userdata).takeUnretainedValue().isCancelled ? 1 : 0
}
