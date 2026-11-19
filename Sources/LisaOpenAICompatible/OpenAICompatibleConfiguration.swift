// The configuration of an OpenAI-compatible model provider: endpoint, model, API key reference, timeout and bounds.

import Foundation
import LisaInference
import LisaSecrets

/// What the provider needs (MODEL-01): the endpoint, the model identifier, an optional API key reference, the request
/// timeout and the configured usage limits (OPS-02).
public struct OpenAICompatibleConfiguration: Hashable, Sendable {
    /// The Chat Completions base address, such as `https://models.example.com/v1` or `http://127.0.0.1:8080/v1`.
    public var endpoint: URL
    /// The model name sent with each request.
    public var model: String
    /// Where the API key is kept, if the endpoint needs one. It is sent as `Authorization: Bearer <key>`.
    public var apiKey: SecretReference?
    /// The time allowed for one request, including connection setup.
    public var requestTimeoutSeconds: Int
    /// Output tokens per request, response size and input size bounds.
    public var limits: ModelUsageLimits
    public var dialect: ChatCompletionsDialect

    public init(
        endpoint: URL, model: String, apiKey: SecretReference? = nil, requestTimeoutSeconds: Int = 60,
        limits: ModelUsageLimits = ModelUsageLimits(), dialect: ChatCompletionsDialect = .standard
    ) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.limits = limits
        self.dialect = dialect
    }

    /// The accepted request timeouts, in seconds.
    public static let timeoutRange = 1...600
    /// The longest model identifier accepted.
    public static let maxModelLength = 200

    /// The largest request body sent: a sanity bound well above what the extraction pipeline produces, whose content
    /// is already cut to `maxInputCharacters` (each character takes at most 4 UTF-8 bytes, and JSON escaping can grow
    /// a control character to 6).
    public var maxRequestBytes: Int { 16 * max(1, limits.maxInputCharacters) + 65_536 }

    /// The largest response body read. The pipeline itself rejects message text beyond `maxResponseBytes`; the body
    /// adds JSON escaping and the surrounding object, so the transport allows twice that plus 32 KiB.
    public var maxResponseBytes: Int { 2 * max(1, limits.maxResponseBytes) + 32_768 }

    /// Checks everything except the endpoint, which `ModelEndpoint` validates.
    func validate() throws(OpenAICompatibleConfigurationError) {
        let modelValid =
            (1...Self.maxModelLength).contains(model.utf8.count)
            && !model.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }
        guard modelValid else {
            throw OpenAICompatibleConfigurationError(
                "the model identifier must be 1 to \(Self.maxModelLength) bytes without control characters")
        }
        guard Self.timeoutRange.contains(requestTimeoutSeconds) else {
            throw OpenAICompatibleConfigurationError("the model request timeout must be 1 to 600 seconds")
        }
        guard limits.maxOutputTokens >= 1, limits.maxResponseBytes >= 1, limits.maxInputCharacters >= 1 else {
            throw OpenAICompatibleConfigurationError("the model limits must be positive")
        }
    }
}
