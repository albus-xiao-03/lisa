// The Swift side of the connect-time address check (SEC-02): libcurl calls it, through the C shim, for every
// resolved address before opening a socket, and for the connected address before sending a request.

import CCurlShim
import LisaHTTP

/// Applies an AddressPolicy to the addresses libcurl is about to use, and remembers what it refused. Created and used
/// on the thread that runs one transfer.
final class CurlAddressGate {
    let policy: AddressPolicy
    private var refused: [AddressClass] = []
    /// The C structure handed to libcurl; valid for the gate's lifetime.
    let cGate: UnsafeMutablePointer<lisa_curl_address_gate>

    init(policy: AddressPolicy) {
        self.policy = policy
        cGate = UnsafeMutablePointer<lisa_curl_address_gate>.allocate(capacity: 1)
        cGate.initialize(to: lisa_curl_address_gate(check: curlAddressCheck, context: nil, request_started: 0))
        cGate.pointee.context = Unmanaged.passUnretained(self).toOpaque()
    }

    deinit {
        cGate.deinitialize(count: 1)
        cGate.deallocate()
    }

    /// Whether the pre-request check passed, after which request bytes may have reached the server. Read only after
    /// the transfer returns, on the thread that ran it.
    var requestStarted: Bool { cGate.pointee.request_started != 0 }

    /// The classes of the addresses refused so far.
    var refusedClasses: [AddressClass] { refused }

    func permits(_ bytes: [UInt8]) -> Bool {
        guard let address = NetworkAddress(bytes: bytes) else { return false }
        if policy.permits(address) { return true }
        refused.append(address.addressClass)
        return false
    }
}

/// Called by the C shim with 4 or 16 address bytes; returns 1 to allow the connection.
private func curlAddressCheck(_ context: UnsafeMutableRawPointer?, _ address: UnsafePointer<UInt8>?, _ length: Int)
    -> Int32
{
    guard let context, let address, length == 4 || length == 16 else { return 0 }
    let gate = Unmanaged<CurlAddressGate>.fromOpaque(context).takeUnretainedValue()
    return gate.permits(Array(UnsafeBufferPointer(start: address, count: length))) ? 1 : 0
}
