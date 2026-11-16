// The transport boundary between clients and the host API: requests, responses and the APITransport protocol.

import Foundation

/// HTTP methods used by the API.
public enum HTTPMethod: String, Codable, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// One API request. The body is JSON produced by `APIJSON.encoder()`.
public struct APIRequest: Hashable, Sendable {
    public var method: HTTPMethod
    /// The path without the query, for example `/v1/tasks/abc`.
    public var path: String
    public var query: [String: String]
    /// Header names are compared case-insensitively by the router.
    public var headers: [String: String]
    public var body: Data?

    public init(
        method: HTTPMethod, path: String, query: [String: String] = [:], headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// The value of a header, ignoring the case of its name.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }
}

/// One API response. Error responses carry an `APIErrorBody`.
public struct APIResponse: Hashable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// The value of a header, ignoring the case of its name.
    public func header(_ name: String) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }
}

/// Why a request could not reach the host at all. A response with an error status is not a transport error.
public enum APITransportError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The host could not be reached; the request may be retried later with the same request ID.
    case unreachable(String)
    /// The connection failed after the request may have been delivered; retry with the same request ID.
    case interrupted(String)
    /// The transport refused the request before sending it, for example because TLS trust failed.
    case refused(String)

    public var description: String {
        switch self {
        case .unreachable(let reason): "the Lisa host could not be reached: \(reason)"
        case .interrupted(let reason): "the connection to the Lisa host was interrupted: \(reason)"
        case .refused(let reason): "the request was not sent: \(reason)"
        }
    }
}

/// Carries requests to a Lisa host: in process (the Mac app's embedded host, the CLI and the demo) or over HTTPS.
public protocol APITransport: Sendable {
    func send(_ request: APIRequest) async throws -> APIResponse
}
