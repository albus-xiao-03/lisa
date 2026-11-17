// X API error details read leniently from any error body: problem types, parameter names and legacy error codes.

import Foundation

/// What an X error body says, reduced to values Lisa can act on. Free text (`title`, `detail`, `message`) is never kept,
/// so nothing from the server reaches an error summary unchecked.
///
/// X sends problem objects (`type`, `title`, `detail`, plus `parameter` and others by type) as
/// `application/problem+json` or JSON, a top-level problem or an `errors` array, and its rate-limit page shows the
/// legacy form `{"errors":[{"code":88,"message":"Rate limit exceeded"}]}`
/// (https://docs.x.com/x-api/fundamentals/response-codes-and-errors.md,
/// https://docs.x.com/x-api/fundamentals/rate-limits.md). All of them are accepted.
struct XProblemDetails: Hashable, Sendable {
    /// Problem types by their last path segment, such as `usage-capped` or `client-forbidden`.
    var types: [String] = []
    /// Parameter names that problems refer to, when they look like parameter names.
    var parameters: [String] = []
    /// Legacy numeric codes, such as 88.
    var codes: [Int] = []

    /// The most problem entries read from one body.
    static let maxEntries = 20

    init(entries: [XProblemEntry] = []) {
        for entry in entries.prefix(Self.maxEntries) {
            if let type = entry.type.flatMap(Self.typeName) { types.append(type) }
            if let parameter = entry.parameter, Self.isParameterName(parameter) { parameters.append(parameter) }
            if let code = entry.code { codes.append(code) }
        }
    }

    /// Reads any of X's error body forms; an unreadable body yields no details.
    static func parse(_ body: Data) -> XProblemDetails {
        guard let envelope = try? JSONDecoder().decode(XErrorEnvelope.self, from: body) else {
            return XProblemDetails()
        }
        return XProblemDetails(entries: [envelope.topLevel] + envelope.errors)
    }

    var isEmpty: Bool { types.isEmpty && parameters.isEmpty && codes.isEmpty }

    func contains(_ type: String) -> Bool { types.contains(type) }

    /// `https://api.x.com/2/problems/usage-capped` becomes `usage-capped`; `about:blank` stays as it is.
    static func typeName(_ uri: String) -> String? {
        let name = uri.split(separator: "/").last.map(String.init) ?? uri
        let allowed =
            (1...64).contains(name.utf8.count)
            && name.utf8.allSatisfy { byte in
                (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x2D || byte == 0x3A
            }
        return allowed ? name : nil
    }

    /// Lowercase ASCII letters, digits, `_` and `.`, starting with a letter, as X's parameter names are.
    static func isParameterName(_ text: String) -> Bool {
        guard let first = text.utf8.first, (0x61...0x7A).contains(first), text.utf8.count <= 40 else { return false }
        return text.utf8.allSatisfy { byte in
            (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x5F || byte == 0x2E
        }
    }
}

/// One problem object or legacy error, with every member optional and type mismatches ignored.
struct XProblemEntry: Decodable, Hashable, Sendable {
    var type: String?
    var parameter: String?
    var code: Int?

    private enum CodingKeys: String, CodingKey {
        case type
        case parameter
        case code
    }

    init(type: String? = nil, parameter: String? = nil, code: Int? = nil) {
        self.type = type
        self.parameter = parameter
        self.code = code
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        parameter = try? container.decodeIfPresent(String.self, forKey: .parameter)
        code = try? container.decodeIfPresent(Int.self, forKey: .code)
    }
}

/// An error body: a top-level problem or error, an `errors` array, or both.
private struct XErrorEnvelope: Decodable {
    var topLevel: XProblemEntry
    var errors: [XProblemEntry]

    private enum CodingKeys: String, CodingKey {
        case errors
    }

    init(from decoder: any Decoder) throws {
        topLevel = try XProblemEntry(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = (try? container.decodeIfPresent([XProblemEntry].self, forKey: .errors)) ?? []
    }
}
