// Reads the error object of an OpenAI-compatible error response leniently: its type, code and parameter name.

import Foundation

/// The official error body is `{"error": {"type", "message", "param", "code"}}` (`ErrorResponse`, `Error`); 401 and
/// 403 may arrive as `text/plain` "JSON-encoded error text". Only short identifier-like values are kept: never the
/// free-text `message`.
struct ChatCompletionsErrorBody: Hashable, Sendable {
    var type: String?
    var code: String?
    var param: String?

    init(type: String? = nil, code: String? = nil, param: String? = nil) {
        self.type = type
        self.code = code
        self.param = param
    }

    /// Reads a body in either form; an unreadable one yields no details.
    static func parse(_ body: Data) -> ChatCompletionsErrorBody {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body), let error = envelope.error else {
            return ChatCompletionsErrorBody()
        }
        return ChatCompletionsErrorBody(
            type: error.type.flatMap(identifier), code: error.code.flatMap(identifier),
            param: error.param.flatMap(identifier))
    }

    /// Lowercase ASCII letters, digits, `_`, `.` and `-`, at most 64 bytes.
    static func identifier(_ text: String) -> String? {
        guard (1...64).contains(text.utf8.count),
            text.utf8.allSatisfy({ byte in
                (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x5F || byte == 0x2E
                    || byte == 0x2D
            })
        else { return nil }
        return text
    }

    private struct Envelope: Decodable {
        var error: ErrorObject?

        private enum CodingKeys: String, CodingKey {
            case error
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            error = try? container.decodeIfPresent(ErrorObject.self, forKey: .error)
        }
    }

    private struct ErrorObject: Decodable {
        var type: String?
        var code: String?
        var param: String?

        private enum CodingKeys: String, CodingKey {
            case type
            case code
            case param
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decodeIfPresent(String.self, forKey: .type)
            code = try? container.decodeIfPresent(String.self, forKey: .code)
            param = try? container.decodeIfPresent(String.self, forKey: .param)
        }
    }
}
