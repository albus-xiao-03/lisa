// One libcurl easy handle with typed option and information accessors. A handle is used by one thread at a time; it
// moves between threads only through CurlHandlePool, never concurrently.

import CCurl
import CCurlShim
import Foundation

/// A libcurl option or information request that failed.
struct CurlOptionError: Error, CustomStringConvertible {
    let description: String
}

/// An easy handle. `@unchecked Sendable` because ownership is transferred, never shared: libcurl forbids using one
/// handle from two threads at once, and every use happens inside a single blocking exchange.
final class CurlEasy: @unchecked Sendable {
    let handle: UnsafeMutableRawPointer
    private var isCleanedUp = false

    init() throws(CurlSetupError) {
        _ = try CurlRuntime.library()
        guard let handle = curl_easy_init() else { throw CurlSetupError("libcurl could not create a handle") }
        self.handle = handle
    }

    deinit { cleanup() }

    /// Closes the handle's connections (curl_easy_cleanup). libcurl may run header and progress callbacks inside it
    /// (IMAP LOGOUT, SMTP QUIT), so callers keep every callback context alive across this call. The handle must not
    /// be used afterwards.
    func cleanup() {
        guard !isCleanedUp else { return }
        isCleanedUp = true
        curl_easy_cleanup(handle)
    }

    /// Restores option defaults, which also clears every callback and its data; live connections and caches stay
    /// (curl_easy_reset).
    func reset() { curl_easy_reset(handle) }

    func set(_ option: CURLoption, _ value: Int) throws(CurlOptionError) {
        try check(lisa_curl_setopt_long(handle, Int32(bitPattern: option.rawValue), value), option)
    }

    func set(_ option: CURLoption, _ value: String?) throws(CurlOptionError) {
        let code: Int32 =
            if let value {
                value.withCString { lisa_curl_setopt_string(handle, Int32(bitPattern: option.rawValue), $0) }
            } else {
                lisa_curl_setopt_string(handle, Int32(bitPattern: option.rawValue), nil)
            }
        try check(code, option)
    }

    func set(_ option: CURLoption, pointer: UnsafeMutableRawPointer?) throws(CurlOptionError) {
        try check(lisa_curl_setopt_pointer(handle, Int32(bitPattern: option.rawValue), pointer), option)
    }

    func set(_ option: CURLoption, offset: Int64) throws(CurlOptionError) {
        try check(lisa_curl_setopt_offset(handle, Int32(bitPattern: option.rawValue), offset), option)
    }

    func long(_ info: CURLINFO) -> Int? {
        var value = 0
        return lisa_curl_getinfo_long(handle, Int32(bitPattern: info.rawValue), &value) == 0 ? value : nil
    }

    func string(_ info: CURLINFO) -> String? {
        var value: UnsafePointer<CChar>?
        guard lisa_curl_getinfo_string(handle, Int32(bitPattern: info.rawValue), &value) == 0, let value else {
            return nil
        }
        return String(cString: value)
    }

    /// The socket of the connection, for waiting on it in connect-only mode.
    func activeSocket() -> Int32? {
        var socket: Int32 = -1
        guard lisa_curl_getinfo_socket(handle, Int32(bitPattern: CURLINFO_ACTIVESOCKET.rawValue), &socket) == 0,
            socket >= 0
        else { return nil }
        return socket
    }

    private func check(_ code: Int32, _ option: CURLoption) throws(CurlOptionError) {
        guard code != 0 else { return }
        let message = String(cString: curl_easy_strerror(CURLcode(UInt32(bitPattern: code))))
        throw CurlOptionError(description: "libcurl refused option \(option.rawValue): \(message)")
    }
}

/// An owned `curl_slist`, freed on deinit. libcurl does not copy lists, so the owner must outlive the transfer.
final class CurlStringList {
    private(set) var head: UnsafeMutablePointer<curl_slist>?

    init(_ strings: [String] = []) throws(CurlOptionError) {
        for string in strings { try append(string) }
    }

    func append(_ string: String) throws(CurlOptionError) {
        guard let next = curl_slist_append(head, string) else {
            throw CurlOptionError(description: "libcurl could not allocate a list entry")
        }
        head = next
    }

    deinit { curl_slist_free_all(head) }
}
