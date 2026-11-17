// Encodes the Chat Completions request body: model, messages, the token limit, temperature and JSON mode.

import Foundation
import LisaInference

/// The request subset Lisa sends (`CreateChatCompletionRequest`, which requires `model` and `messages`):
/// - `model` and `messages`, with `system`, `user` and `assistant` roles and plain string content. `system` rather than
///   `developer` keeps local servers working; the specification still defines the system message.
/// - the token limit, in the field the dialect names, capped by the configured `maxOutputTokens`;
/// - `temperature`, clamped to the specification's 0 to 2, unless the dialect leaves it out;
/// - `response_format: {"type": "json_object"}` when the caller wants JSON and the dialect allows it;
/// - `stream: false`, so the reply is one JSON object rather than server-sent events.
///
/// Nothing else is sent: no tools, no `n` (the default is 1), no `store` (the default is `false`), no user
/// identifiers.
struct ChatCompletionsRequestBody: Encodable, Sendable {
    struct Message: Encodable, Hashable, Sendable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var tokenLimitField: ChatCompletionsDialect.TokenLimitField
    var tokenLimit: Int
    var temperature: Double?
    var requestsJSONObject: Bool

    init(_ request: ModelRequest, model: String, dialect: ChatCompletionsDialect, maxOutputTokens: Int) {
        self.model = model
        messages = request.messages.map { Message(role: $0.role.rawValue, content: $0.content) }
        tokenLimitField = dialect.tokenLimitField
        tokenLimit = max(1, min(request.maxOutputTokens, maxOutputTokens))
        let clamped = request.temperature.isFinite ? min(max(request.temperature, 0), 2) : 0
        temperature = dialect.sendsTemperature ? clamped : nil
        requestsJSONObject = request.wantsJSON && dialect.requestsJSONObject
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private struct ResponseFormat: Encodable {
        var type = "json_object"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(model, forKey: Key("model"))
        try container.encode(messages, forKey: Key("messages"))
        try container.encode(tokenLimit, forKey: Key(tokenLimitField.rawValue))
        if let temperature { try container.encode(temperature, forKey: Key("temperature")) }
        if requestsJSONObject { try container.encode(ResponseFormat(), forKey: Key("response_format")) }
        try container.encode(false, forKey: Key("stream"))
    }

    /// The JSON body, with sorted keys so identical requests produce identical bytes.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
