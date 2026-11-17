// The compatibility choices for an OpenAI-compatible server: the token-limit field, temperature and JSON mode.

/// Which optional request fields Lisa sends. Servers that call themselves OpenAI-compatible differ in which of these
/// they accept, so each choice is explicit here instead of being assumed from a server's description (MODEL-01).
///
/// The official OpenAPI specification (https://raw.githubusercontent.com/openai/openai-openapi/master/openapi.yaml,
/// `info.version` 2.3.0, `CreateChatCompletionRequest`) defines `max_completion_tokens` and marks `max_tokens` as
/// "deprecated in favor of `max_completion_tokens`, and is not compatible with o-series models". The default still
/// sends `max_tokens`: the default data-sharing policy allows only local model servers (the example configuration
/// points at one on `127.0.0.1:8080`), and `max_tokens` is the field such servers have long implemented, whereas a
/// server that does not know `max_completion_tokens` would most likely ignore it and generate without a limit. A
/// server that rejects `max_tokens` fails loudly instead (HTTP 400, reported with the parameter's name). Endpoints that
/// require the newer field, such as o-series models, use `.maxCompletionTokens`. Neither default has been checked
/// against a real server here (NOT_RUN_CREDENTIALS).
public struct ChatCompletionsDialect: Hashable, Sendable {
    /// The request field that bounds generated tokens.
    public enum TokenLimitField: String, Hashable, Sendable, CaseIterable {
        /// `max_tokens`: deprecated in the official specification, widely implemented by local servers.
        case maxTokens = "max_tokens"
        /// `max_completion_tokens`: the official field, which also counts reasoning tokens.
        case maxCompletionTokens = "max_completion_tokens"
    }

    public var tokenLimitField: TokenLimitField
    /// Whether `temperature` (0 to 2) is sent. Some reasoning models accept only their default.
    public var sendsTemperature: Bool
    /// Whether `response_format: {"type": "json_object"}` ("the older JSON mode") is sent when the caller wants JSON.
    /// The extraction prompt asks for JSON itself, and validation accepts a fenced reply, so servers that reject the
    /// field still work with this off.
    public var requestsJSONObject: Bool

    public init(
        tokenLimitField: TokenLimitField = .maxTokens, sendsTemperature: Bool = true, requestsJSONObject: Bool = true
    ) {
        self.tokenLimitField = tokenLimitField
        self.sendsTemperature = sendsTemperature
        self.requestsJSONObject = requestsJSONObject
    }

    /// `max_tokens`, `temperature` and JSON mode.
    public static let standard = ChatCompletionsDialect()
}
