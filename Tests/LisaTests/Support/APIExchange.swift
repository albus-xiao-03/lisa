// Test-only. Builds API requests as a client puts them on the wire (route, query, JSON body, request ID, bearer
// credential) for checks below the typed client, and reads success and typed error bodies back. Used by the API
// suites (L20, L21) and later device suites.

import Foundation
import LisaAPIContract
import Testing

/// Raw API requests and responses.
enum APIExchange {
    /// The keys an error body may have (docs/API.md, "Errors").
    static let errorBodyKeys: Set<String> = ["code", "message", "field", "retryAfterSeconds", "currentRevision"]

    /// A request for `route`, with `body` as JSON when given.
    static func request(
        _ route: APIRoute, query: [String: String] = [:], body: Data? = nil, requestID: String? = nil,
        credential: String? = nil
    ) -> APIRequest {
        var headers: [String: String] = [:]
        if let requestID { headers[APIVersioning.requestIDHeader] = requestID }
        if let credential { headers[APIVersioning.authorizationHeader] = "Bearer \(credential)" }
        if body != nil { headers["Content-Type"] = "application/json" }
        return APIRequest(method: route.method, path: route.path, query: query, headers: headers, body: body)
    }

    /// `value` in the contract's JSON coding.
    static func json(_ value: some Encodable) throws -> Data {
        try APIJSON.encoder().encode(value)
    }

    /// A body written as JSON text, for hand-shaped or malformed bodies.
    static func json(text: String) -> Data {
        Data(text.utf8)
    }

    /// The success body decoded as `type`.
    static func decode<T: Decodable>(_ type: T.Type, _ response: APIResponse) throws -> T {
        try APIJSON.decoder().decode(type, from: response.body)
    }

    /// The typed error body of an error response.
    static func error(_ response: APIResponse) throws -> APIErrorBody {
        try APIJSON.decoder().decode(APIErrorBody.self, from: response.body)
    }

    /// The top-level keys of a JSON object body; empty when the body is not a JSON object.
    static func keys(_ response: APIResponse) -> Set<String> {
        guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { return [] }
        return Set(object.keys)
    }

    /// Checks that `response` is the typed error `code` as docs/API.md documents it: the code's status, the version
    /// header, a body with only the documented keys and a message, and `field` when one is given. Returns the body.
    @discardableResult
    static func expectError(
        _ response: APIResponse, _ code: APIErrorCode, field: String? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> APIErrorBody? {
        #expect(response.status == code.httpStatus, sourceLocation: sourceLocation)
        #expect(response.header(APIVersioning.versionHeader) == APIVersioning.version, sourceLocation: sourceLocation)
        #expect(keys(response).isSubset(of: errorBodyKeys), sourceLocation: sourceLocation)
        guard let body = try? error(response) else {
            Issue.record("the \(response.status) response has no typed error body", sourceLocation: sourceLocation)
            return nil
        }
        #expect(body.code == code, sourceLocation: sourceLocation)
        #expect(!body.message.isEmpty, sourceLocation: sourceLocation)
        if let field { #expect(body.field == field, sourceLocation: sourceLocation) }
        return body
    }

    /// Whether the response replays an answer the host recorded earlier (`Lisa-Replayed: true`).
    static func isReplay(_ response: APIResponse) -> Bool {
        response.header("Lisa-Replayed") == "true"
    }
}
