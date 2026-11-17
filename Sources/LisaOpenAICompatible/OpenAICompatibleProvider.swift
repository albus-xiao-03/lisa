// The OpenAI-compatible model provider: one Chat Completions request per completion, bounded and policy-checked.

import Foundation
import LisaHTTP
import LisaInference
import LisaRedaction
import LisaSecrets

/// A `ModelProvider` for an OpenAI-compatible Chat Completions endpoint (MODEL-01): `POST <endpoint>/chat/completions`
/// with the request subset described by `ChatCompletionsRequestBody` and `ChatCompletionsDialect`.
///
/// Each completion is exactly one HTTP request: no retries, no redirects, no streaming. The request body, the reply
/// and the time are bounded; the address policy and the descriptor's location follow from the endpoint
/// (`ModelEndpoint`). The optional API key is resolved for each request and sent only as `Authorization: Bearer`.
///
/// What callers already do is not repeated: the extraction pipeline checks the data-sharing policy against
/// `descriptor.location`, minimizes and truncates content for remote endpoints, validates the reply's JSON and size,
/// and makes at most one repair attempt. Failures are `ModelError`s: unavailable (unreachable, misconfigured or
/// failing endpoint, or an unreadable key), authentication (401, 403), rate limited (429, with `Retry-After`),
/// timeout, refused by policy (nothing sent) and invalid response.
public struct OpenAICompatibleProvider: ModelProvider {
    public let descriptor: ModelDescriptor
    public let configuration: OpenAICompatibleConfiguration
    public let endpoint: ModelEndpoint
    private let secrets: any SecretStore
    private let http: any HTTPClient
    private let now: @Sendable () -> Date

    /// The longest time allowed for connection setup, within the request timeout.
    static let connectTimeoutSeconds = 10.0

    /// - Parameters:
    ///   - secrets: resolves `configuration.apiKey` for each request.
    ///   - http: the transport (`CurlHTTPClient` in the host).
    ///   - now: the current instant, from the host's clock; used for `Retry-After` dates.
    public init(
        configuration: OpenAICompatibleConfiguration, secrets: any SecretStore, http: any HTTPClient,
        now: @escaping @Sendable () -> Date
    ) throws(OpenAICompatibleConfigurationError) {
        try configuration.validate()
        let endpoint = try ModelEndpoint(base: configuration.endpoint)
        self.configuration = configuration
        self.endpoint = endpoint
        self.secrets = secrets
        self.http = http
        self.now = now
        descriptor = ModelDescriptor(
            name: "\(configuration.model) (OpenAI-compatible, \(endpoint.origin))", location: endpoint.location,
            isDeterministic: false)
    }

    public func complete(_ request: ModelRequest) async throws -> ModelResponse {
        guard !request.messages.isEmpty else { throw ModelError.refusedByPolicy("a request without messages") }
        try Task.checkCancellation()
        let body: Data
        do {
            body = try ChatCompletionsRequestBody(
                request, model: configuration.model, dialect: configuration.dialect,
                maxOutputTokens: configuration.limits.maxOutputTokens
            ).encoded()
        } catch {
            throw ModelError.refusedByPolicy("the request could not be encoded")
        }
        guard body.count <= configuration.maxRequestBytes else { throw ModelError.requestTooLarge }
        var headers = [HTTPHeader("Content-Type", "application/json"), HTTPHeader("Accept", "application/json")]
        if let reference = configuration.apiKey {
            let key = try ModelAPIKey.resolve(reference, from: secrets)
            headers.append(HTTPHeader("Authorization", "Bearer \(key.revealed)", sensitive: true))
        }
        let timeout = Double(configuration.requestTimeoutSeconds)
        let exchange = HTTPRequest(
            method: "POST", url: endpoint.completionsURL, headers: headers, body: body, timeoutSeconds: timeout,
            connectTimeoutSeconds: min(Self.connectTimeoutSeconds, timeout),
            maxResponseBytes: configuration.maxResponseBytes, version: .any, redirects: .none,
            addresses: endpoint.addresses)
        let response: HTTPResponse
        do {
            response = try await http.send(exchange)
        } catch {
            throw ModelTransportFailureMapping.error(for: error)
        }
        guard response.status == 200 else { throw ChatCompletionsStatusMapping.error(for: response, now: now()) }
        return try ChatCompletionsResponseBody.decode(response.body).modelResponse()
    }
}
