// The HTTP request of one APNs push: POST over HTTP/2 only, to public addresses only, without redirects, with bounded
// time and response size.

import Foundation
import LisaHTTP

/// Request assembly and its limits.
public enum APNsRequest {
    /// The whole exchange, including connection setup.
    public static let timeoutSeconds: Double = 30
    /// DNS, TCP and TLS setup.
    public static let connectTimeoutSeconds: Double = 10
    /// APNs answers with an empty body or a small JSON error object (S13); anything larger is aborted.
    public static let maxResponseBytes = APNsErrorBody.maxBytes
    /// The response header block limit.
    public static let maxHeaderBytes = 16_384

    /// The request for `url` with `headers` and the JSON `payload`. HTTP/2 is required without any HTTP/1.1
    /// fallback, the address must be public, and redirects are never followed.
    public static func make(url: URL, headers: [HTTPHeader], payload: Data) -> HTTPRequest {
        HTTPRequest(
            method: "POST", url: url, headers: headers, body: payload, timeoutSeconds: timeoutSeconds,
            connectTimeoutSeconds: connectTimeoutSeconds, maxResponseBytes: maxResponseBytes,
            maxHeaderBytes: maxHeaderBytes, version: .http2Only, redirects: .none, addresses: .publicOnly)
    }
}
