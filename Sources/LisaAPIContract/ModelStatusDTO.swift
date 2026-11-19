// The model configuration that health reports (MODEL-01, UI-01): the provider, the model's name, where it runs,
// whether the host set it up, and the daily request limit. Never an endpoint address, a key reference or a credential.

import Foundation

/// The host's model configuration, as `GET /v1/health` reports it in `HealthDTO.model`. It never contains the
/// endpoint's address, the API key's reference or any credential.
public struct ModelStatusDTO: Codable, Hashable, Sendable {
    /// The configured provider: `none`, `deterministic` or `openAICompatible`, as in the configuration's
    /// `model.provider`.
    public var provider: String
    /// The model's name: `deterministic-rules` for the deterministic provider, or the configured model identifier of
    /// an OpenAI-compatible endpoint; `nil` when no model is configured.
    public var name: String?
    /// Where the provider runs: `inProcess`, `localNetwork` or `remote`; `nil` when no model is configured or the
    /// configured endpoint is not a usable address.
    public var location: String?
    /// True for the rule-based provider, whose output is never presented as live inference.
    public var deterministic: Bool
    /// Whether the host set the provider up when it started. `false` when no model is configured or the configured
    /// endpoint cannot be used; items that need a model then wait (MODEL-04). It does not say that an endpoint answers.
    public var available: Bool
    /// The configured limit of model requests in one local day; `nil` when requests are not counted, as for the
    /// deterministic provider, which sends nothing anywhere.
    public var dailyRequestLimit: Int?

    public init(
        provider: String, name: String?, location: String?, deterministic: Bool, available: Bool,
        dailyRequestLimit: Int?
    ) {
        self.provider = provider
        self.name = name
        self.location = location
        self.deterministic = deterministic
        self.available = available
        self.dailyRequestLimit = dailyRequestLimit
    }
}
