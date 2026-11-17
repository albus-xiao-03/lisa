// The answers the server gives itself, before or instead of the router: malformed requests, oversized headers or
// bodies, unsupported methods and expectations. Their bodies are typed API errors (API-03) that echo nothing.

import Foundation
import LisaAPIContract

/// A request the server refuses. The connection is always closed after the answer.
struct ServerRejection: Error, Hashable, Sendable {
    var status: Int
    var body: APIErrorBody
    var headers: [String: String] = [:]

    static let malformed = ServerRejection(
        status: 400, body: APIErrorBody(code: .invalidRequest, message: "the request is not valid HTTP/1.1"))

    /// RFC 6585 §5: the request line or header fields exceed the server's limit.
    static let headersTooLarge = ServerRejection(
        status: 431, body: APIErrorBody(code: .invalidRequest, message: "the request header fields are too large"))

    /// Only the API's methods are served.
    static let methodNotAllowed = ServerRejection(
        status: 405, body: APIErrorBody(code: .invalidRequest, message: "the request method is not supported"),
        headers: ["Allow": "GET, POST, PUT, PATCH, DELETE"])

    /// RFC 9110 §10.1.1: an expectation other than `100-continue`.
    static let expectationFailed = ServerRejection(
        status: 417,
        body: APIErrorBody(code: .invalidRequest, message: "only the 100-continue expectation is supported"))

    static func payloadTooLarge(limit: Int) -> ServerRejection {
        ServerRejection(
            status: 413, body: APIErrorBody(code: .payloadTooLarge, message: "the request body exceeds \(limit) bytes"))
    }

    static func invalid(_ message: String) -> ServerRejection {
        ServerRejection(status: 400, body: APIErrorBody(code: .invalidRequest, message: message))
    }

    /// The response, in the same JSON form the router uses for errors.
    var response: APIResponse {
        var headers = headers
        headers["Content-Type"] = "application/json"
        headers[APIVersioning.versionHeader] = APIVersioning.version
        let data = (try? APIJSON.encoder().encode(body)) ?? Data()
        return APIResponse(status: status, headers: headers, body: data)
    }
}
