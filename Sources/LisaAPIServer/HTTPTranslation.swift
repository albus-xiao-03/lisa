// Translation between NIO's HTTP/1.1 messages and the API's transport-independent requests and responses: origin-form
// targets with strict percent-decoding, header fields that may appear only once, and the headers every response
// carries.

import Foundation
import LisaAPIContract
import NIOCore
import NIOHTTP1

enum HTTPTranslation {
    /// Request header fields that may appear at most once; a repeat is refused rather than guessed at.
    static let singletonFields: Set<String> = [
        "authorization", "content-type", "content-length", "host", "expect", "lisa-request-id",
    ]

    /// Connection-level fields the router never sees, and the framing the encoder sets itself.
    static let connectionFields: Set<String> = [
        "connection", "keep-alive", "proxy-connection", "te", "trailer", "transfer-encoding", "upgrade", "expect",
        "content-length",
    ]

    /// The API request for a complete HTTP request.
    static func request(head: HTTPRequestHead, body: ByteBuffer?) throws(ServerRejection) -> APIRequest {
        guard let method = LisaAPIContract.HTTPMethod(rawValue: head.method.rawValue) else {
            throw .methodNotAllowed
        }
        var headers: [String: String] = [:]
        var hostFields = 0
        for (rawName, value) in head.headers {
            let name = rawName.lowercased()
            if name == "host" { hostFields += 1 }
            if let existing = headers[name] {
                if singletonFields.contains(name) { throw .invalid("the \(name) header field appears more than once") }
                headers[name] = existing + ", " + value
            } else if !connectionFields.contains(name) || singletonFields.contains(name) {
                headers[name] = value
            }
        }
        if head.version == .http1_1 && hostFields != 1 {
            throw .invalid("an HTTP/1.1 request needs exactly one host header field")
        }
        for name in connectionFields { headers.removeValue(forKey: name) }
        let (path, query) = try target(head.uri)
        let data = body.flatMap { $0.readableBytes > 0 ? Data($0.readableBytesView) : nil }
        return APIRequest(method: method, path: path, query: query, headers: headers, body: data)
    }

    /// The decoded path and query of an origin-form request target.
    static func target(_ uri: String) throws(ServerRejection) -> (path: String, query: [String: String]) {
        guard uri.hasPrefix("/"), !uri.contains("#") else { throw .invalid("the request target must be a path") }
        let parts = uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var segments: [String] = []
        for segment in parts[0].split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
            guard let decoded = PercentDecoding.decode(segment), !decoded.contains("/") else {
                throw .invalid("the request path is not validly encoded")
            }
            segments.append(decoded)
        }
        var query: [String: String] = [:]
        if parts.count == 2 {
            for item in parts[1].split(separator: "&") {
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = PercentDecoding.decode(pair[0]), !name.isEmpty,
                    let value = PercentDecoding.decode(pair.count == 2 ? pair[1] : "")
                else {
                    throw .invalid("the query is not validly encoded")
                }
                guard query[name] == nil else { throw .invalid("a query parameter appears more than once") }
                query[name] = value
            }
        }
        return ("/" + segments.joined(separator: "/"), query)
    }

    /// The head and body of a response. Every response forbids caching and content sniffing; a 401 names the
    /// Bearer scheme (RFC 9110 §11.6.1); a response that ends the connection says so.
    static func responseParts(_ response: APIResponse, version: HTTPVersion, keepAlive: Bool) -> (
        HTTPResponseHead, ByteBuffer
    ) {
        var headers = HTTPHeaders()
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key })
        where !connectionFields.contains(name.lowercased()) {
            headers.add(name: name, value: value)
        }
        headers.replaceOrAdd(name: "Content-Length", value: String(response.body.count))
        headers.replaceOrAdd(name: "Cache-Control", value: "no-store")
        headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        if response.status == 401 && !headers.contains(name: "WWW-Authenticate") {
            headers.add(name: "WWW-Authenticate", value: "Bearer realm=\"lisa\"")
        }
        if !keepAlive {
            headers.replaceOrAdd(name: "Connection", value: "close")
        } else if version.minor == 0 {
            headers.replaceOrAdd(name: "Connection", value: "keep-alive")
        }
        let head = HTTPResponseHead(
            version: version, status: HTTPResponseStatus(statusCode: response.status), headers: headers)
        return (head, ByteBuffer(bytes: response.body))
    }
}
