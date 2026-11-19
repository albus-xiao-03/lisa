// Test-only. A raw HTTP/1.1 exchange over a TCP connection to 127.0.0.1, for the network server's own framing rules
// (docs/API.md, "Errors") that well-formed clients such as URLSession never break: the request bytes are sent exactly
// as written and the response is read until the server closes the connection. Blocking socket calls run on their own
// thread, never on the test's cooperative threads. Loopback only. Used by the network API suite (L20) and later
// network suites.

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// A response read from a raw connection.
struct RawHTTPResponse: Sendable {
    var status: Int
    /// Header fields by lower-cased name; repeated fields are joined with ", ".
    var headers: [String: String]
    var body: Data
}

/// Raw HTTP/1.1 exchanges with a server on 127.0.0.1.
enum RawHTTPExchange {
    /// Why an exchange failed.
    enum Failure: Error, CustomStringConvertible {
        case socket(String)
        /// The server neither answered nor closed the connection in time.
        case timedOut
        case malformedResponse

        var description: String {
            switch self {
            case .socket(let detail): "socket failure: \(detail)"
            case .timedOut: "the server did not close the connection in time"
            case .malformedResponse: "the server's answer is not an HTTP/1.1 response"
            }
        }
    }

    /// Sends `request` as written to 127.0.0.1:`port`, reads until the server closes the connection, and returns the
    /// final (non-1xx) response. A server that keeps the connection open longer than `timeoutSeconds` fails the
    /// exchange with ``Failure/timedOut``.
    static func exchange(port: Int, request: Data, timeoutSeconds: Int = 15) async throws -> RawHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                continuation.resume(
                    with: Result { try blockingExchange(port: port, request: request, timeoutSeconds: timeoutSeconds) })
            }
            thread.start()
        }
    }

    /// `text` with every `\n` written as CRLF, for readable request literals.
    static func crlf(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    private static func blockingExchange(port: Int, request: Data, timeoutSeconds: Int) throws -> RawHTTPResponse {
        #if canImport(Glibc)
            let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard descriptor >= 0 else { throw Failure.socket("socket() failed with errno \(errno)") }
        defer { close(descriptor) }
        var timeout = timeval(tv_sec: .init(timeoutSeconds), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        #if canImport(Darwin)
            var noSignal: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        #endif
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw Failure.socket("connect() failed with errno \(errno)") }
        transmit(request, on: descriptor)
        return try parse(try receiveUntilClosed(descriptor))
    }

    /// Sends every byte it can. A server that closes the connection early (after refusing the request) ends the
    /// sending; its answer is still read.
    private static func transmit(_ data: Data, on descriptor: Int32) {
        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags: Int32 = 0
        #endif
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let sent = send(descriptor, base + offset, buffer.count - offset, flags)
                if sent > 0 {
                    offset += sent
                } else if sent < 0 && errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    private static func receiveUntilClosed(_ descriptor: Int32) throws -> Data {
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                received.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                return received
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw Failure.timedOut
            } else if errno == ECONNRESET && !received.isEmpty {
                return received
            } else {
                throw Failure.socket("recv() failed with errno \(errno)")
            }
        }
    }

    /// The final response in `data`, skipping interim (1xx) responses.
    static func parse(_ data: Data) throws -> RawHTTPResponse {
        let separator = Data("\r\n\r\n".utf8)
        var rest = data
        while true {
            guard let end = rest.range(of: separator) else { throw Failure.malformedResponse }
            var lines = String(decoding: rest[rest.startIndex..<end.lowerBound], as: UTF8.self)
                .components(separatedBy: "\r\n")
            let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2)
            guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."), let status = Int(statusLine[1]) else {
                throw Failure.malformedResponse
            }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = line[..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = headers[name].map { $0 + ", " + value } ?? value
            }
            let remainder = Data(rest[end.upperBound...])
            if (100..<200).contains(status) {
                rest = remainder
                continue
            }
            let length = headers["content-length"].flatMap { Int($0) } ?? remainder.count
            return RawHTTPResponse(status: status, headers: headers, body: Data(remainder.prefix(length)))
        }
    }
}
