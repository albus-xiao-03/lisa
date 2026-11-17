// The per-exchange state libcurl's write and header callbacks fill: the body within its size limit and the header
// fields of the final response.

import CCurlShim
import Foundation
import LisaHTTP

/// Collects one exchange's response. Used only on the exchange's thread.
final class CurlTransfer {
    let maxBodyBytes: Int
    let maxHeaderBytes: Int
    private(set) var body = Data()
    private(set) var headers: [HTTPHeader] = []
    private(set) var headerBytes = 0
    private(set) var bodyTooLarge = false
    private(set) var headersTooLarge = false
    /// Whether any response bytes arrived, which shows the request was sent.
    private(set) var receivedResponse = false
    /// Every server line as received, for mail protocols, whose "headers" are the server's command responses.
    private(set) var lines: [String] = []
    let recordsLines: Bool

    init(maxBodyBytes: Int, maxHeaderBytes: Int, recordsLines: Bool = false) {
        self.maxBodyBytes = maxBodyBytes
        self.maxHeaderBytes = maxHeaderBytes
        self.recordsLines = recordsLines
    }

    var userdata: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    /// Appends body bytes; false aborts the transfer.
    func receiveBody(_ bytes: UnsafeRawBufferPointer) -> Bool {
        receivedResponse = true
        guard body.count + bytes.count <= maxBodyBytes else {
            bodyTooLarge = true
            return false
        }
        body.append(contentsOf: bytes)
        return true
    }

    /// Records one header line; false aborts the transfer. A new status line starts a new header block, so only the
    /// final response's fields are kept (after 1xx responses).
    func receiveHeaderLine(_ bytes: UnsafeRawBufferPointer) -> Bool {
        receivedResponse = true
        headerBytes += bytes.count
        guard headerBytes <= maxHeaderBytes else {
            headersTooLarge = true
            return false
        }
        // Line endings are trimmed as bytes: Swift treats CR LF as one Character, so hasSuffix("\n") misses it.
        var end = bytes.count
        while end > 0, bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D { end -= 1 }
        let line = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[0..<end]), as: UTF8.self)
        if recordsLines {
            lines.append(line)
            return true
        }
        if line.hasPrefix("HTTP/") {
            headers.removeAll()
            return true
        }
        guard !line.isEmpty else { return true }
        if line.first == " " || line.first == "\t", !headers.isEmpty {
            // An obsolete folded continuation line (libcurl 8.14.1 does not unfold them).
            headers[headers.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
            return true
        }
        guard let colon = line.firstIndex(of: ":") else { return true }
        let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        headers.append(HTTPHeader(name, value))
        return true
    }
}

/// libcurl write callback: body bytes for the CurlTransfer in `userdata`.
let curlWriteBody: lisa_curl_data_callback = { buffer, size, count, userdata in
    guard let userdata else { return 0 }
    let transfer = Unmanaged<CurlTransfer>.fromOpaque(userdata).takeUnretainedValue()
    let length = size * count
    guard length > 0, let buffer else { return 0 }
    return transfer.receiveBody(UnsafeRawBufferPointer(start: buffer, count: length)) ? length : 0
}

/// libcurl header callback: one header line for the CurlTransfer in `userdata`.
let curlWriteHeader: lisa_curl_data_callback = { buffer, size, count, userdata in
    guard let userdata else { return 0 }
    let transfer = Unmanaged<CurlTransfer>.fromOpaque(userdata).takeUnretainedValue()
    let length = size * count
    guard length > 0, let buffer else { return 0 }
    return transfer.receiveHeaderLine(UnsafeRawBufferPointer(start: buffer, count: length)) ? length : 0
}
