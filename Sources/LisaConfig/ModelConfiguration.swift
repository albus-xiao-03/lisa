// The `model` section: the model provider, its endpoint and credentials, the data-sharing policy and usage limits.

import Foundation
import LisaSecrets

/// Which model provider Lisa uses (MODEL-01).
public enum ModelProviderKind: String, Hashable, Sendable, CaseIterable {
    /// No model: items that need interpretation wait, and everything else keeps working (MODEL-04).
    case none
    /// The in-process deterministic provider, which sends nothing anywhere. The default.
    case deterministic
    /// An OpenAI-compatible Chat Completions endpoint.
    case openAICompatible
}

/// What may be sent to a model. The raw values match the inference module's `ModelDataSharing`.
public enum ModelDataSharingPolicy: String, Hashable, Sendable, CaseIterable {
    /// Nothing leaves the process: only the deterministic provider may be used.
    case none
    /// Content may go only to an endpoint on this machine or a private network. The default.
    case localOnly
    /// A remote endpoint may receive minimized content, with addresses, numbers and links removed.
    case remoteMinimized
}

/// Bounds on model use (OPS-02). The defaults match the inference module's `ModelUsageLimits()`.
public struct ModelLimits: Hashable, Sendable {
    /// The most characters of content sent in one request.
    public let maxInputCharacters: Int
    /// The most tokens a response may generate.
    public let maxOutputTokens: Int
    /// The most requests in a local day.
    public let maxRequestsPerDay: Int
    /// The largest response accepted, in bytes.
    public let maxResponseBytes: Int
    /// The most extracted items accepted from one response.
    public let maxItems: Int

    /// 12,000 input characters, 1,200 output tokens, 500 requests a day, 64 KiB responses and 25 items.
    public static let defaultValue = ModelLimits(
        maxInputCharacters: 12_000, maxOutputTokens: 1_200, maxRequestsPerDay: 500, maxResponseBytes: 65_536,
        maxItems: 25)

    static func decode(_ section: ConfigSection?) -> ModelLimits {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return ModelLimits(
            maxInputCharacters: section.integer(
                "maxInputCharacters", default: defaults.maxInputCharacters, in: 500...200_000),
            maxOutputTokens: section.integer("maxOutputTokens", default: defaults.maxOutputTokens, in: 16...32_768),
            maxRequestsPerDay: section.integer(
                "maxRequestsPerDay", default: defaults.maxRequestsPerDay, in: 1...100_000),
            maxResponseBytes: section.integer(
                "maxResponseBytes", default: defaults.maxResponseBytes, in: 1024...4_194_304),
            maxItems: section.integer("maxItems", default: defaults.maxItems, in: 1...100))
    }
}

/// Model access (MODEL-01, MODEL-04, SEC-03). The default is the deterministic provider with local-only sharing, so
/// nothing is sent anywhere; a cloud endpoint needs both an explicit endpoint and an explicit sharing policy.
public struct ModelConfiguration: Hashable, Sendable {
    /// The provider in use; `deterministic` by default.
    public let provider: ModelProviderKind
    /// The Chat Completions base address: https, or plain http to a loopback address only. Required for
    /// `openAICompatible`; it may be set in advance while another provider is selected.
    public let endpoint: URL?
    /// Where `endpoint` points, judged from its host: only IP literals and `localhost` count as local.
    public let endpointScope: NetworkScope?
    /// The model name sent with each request. Required for `openAICompatible`.
    public let modelIdentifier: String?
    /// The reference to the endpoint's API key, if it needs one.
    public let apiKeySecret: SecretReference?
    /// What may be sent to the provider; `localOnly` by default.
    public let dataSharing: ModelDataSharingPolicy
    /// The time allowed for one request.
    public let requestTimeoutSeconds: Int
    /// Bounds on input, output, request count and response size.
    public let limits: ModelLimits

    /// The deterministic provider, local-only sharing, no endpoint, a 60-second timeout and the default limits.
    public static let defaultValue = ModelConfiguration(
        provider: .deterministic, endpoint: nil, endpointScope: nil, modelIdentifier: nil, apiKeySecret: nil,
        dataSharing: .localOnly, requestTimeoutSeconds: 60, limits: .defaultValue)

    static func decode(_ section: ConfigSection?) -> ModelConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        let endpoint = section.validated("endpoint", maxLength: 2048, NetworkAddressRules.modelEndpoint)
        return ModelConfiguration(
            provider: section.choice("provider", default: defaults.provider, options: ModelProviderKind.allCases),
            endpoint: endpoint,
            endpointScope: endpoint.flatMap(NetworkAddressRules.host(of:)).map(NetworkScope.of(host:)),
            modelIdentifier: section.text("modelIdentifier", maxLength: 200),
            apiKeySecret: section.secret("apiKeySecret"),
            dataSharing: section.choice(
                "dataSharing", default: defaults.dataSharing, options: ModelDataSharingPolicy.allCases),
            requestTimeoutSeconds: section.integer(
                "requestTimeoutSeconds", default: defaults.requestTimeoutSeconds, in: 5...600),
            limits: ModelLimits.decode(section.section("limits")))
    }
}
