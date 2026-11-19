// Reads host responses: the API major-version check, error bodies, and success bodies as JSON or text.

import Foundation
import LisaAPIContract

/// Interprets `APIResponse` values for the client.
enum ResponseInterpreter {
    /// The API major version this client speaks, taken from `APIVersioning.version`.
    static let supportedMajorVersion = majorVersion(of: APIVersioning.version) ?? 1

    /// The value of a response header, ignoring the case of its name.
    static func header(_ name: String, in headers: [String: String]) -> String? {
        let lowered = name.lowercased()
        return headers.first { $0.key.lowercased() == lowered }?.value
    }

    /// Rejects a response whose `Lisa-API-Version` major version is not the supported one. A response without the
    /// header is accepted.
    static func checkVersion(of response: APIResponse) throws(ClientError) {
        guard let value = header(APIVersioning.versionHeader, in: response.headers) else { return }
        guard majorVersion(of: value) == supportedMajorVersion else { throw .incompatibleVersion(value) }
    }

    /// The error for a response outside 2xx: the typed API error when the body is one.
    static func failure(for response: APIResponse) -> ClientError {
        guard let body = try? APIJSON.decoder().decode(APIErrorBody.self, from: response.body) else {
            return .unexpectedResponse(status: response.status)
        }
        return .api(body, status: response.status)
    }

    /// Decodes a JSON success body.
    static func decode<Value: Decodable>(_ type: Value.Type, from response: APIResponse) throws(ClientError) -> Value {
        do {
            return try APIJSON.decoder().decode(type, from: response.body)
        } catch let error as DecodingError {
            throw .decoding(describe(error, decoding: type))
        } catch {
            throw .decoding("\(type): the body could not be decoded")
        }
    }

    /// A UTF-8 text success body, such as an iCalendar file.
    static func text(from response: APIResponse) throws(ClientError) -> String {
        guard let text = String(data: response.body, encoding: .utf8) else {
            throw .decoding("the response body is not UTF-8 text")
        }
        return text
    }

    /// The major version of a `major.minor` version string.
    static func majorVersion(of value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespaces).prefix { $0 != "." })
    }

    /// Describes a decoding failure by type and coding path only, so response values never reach logs.
    private static func describe<Value>(_ error: DecodingError, decoding type: Value.Type) -> String {
        let detail: (context: DecodingError.Context, problem: String)
        switch error {
        case .typeMismatch(_, let context): detail = (context, "a value has the wrong type")
        case .valueNotFound(_, let context): detail = (context, "a required value is missing")
        case .keyNotFound(let key, let context): detail = (context, "the key \"\(key.stringValue)\" is missing")
        case .dataCorrupted(let context): detail = (context, "the data is malformed")
        @unknown default: return "\(type): the body could not be decoded"
        }
        let path = detail.context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "\(type): \(detail.problem)" : "\(type) at \(path): \(detail.problem)"
    }
}
