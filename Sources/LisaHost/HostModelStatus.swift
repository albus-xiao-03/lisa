// What health reports about the configured model (MODEL-01, UI-01): built from the model settings and the provider
// the host set up, without the endpoint's address, the API key's reference or any credential.

import Foundation
import LisaAPIContract
import LisaInference
import LisaOpenAICompatible

/// Builds the model configuration that `GET /v1/health` reports (`HealthDTO.model`).
enum HostModelStatus {
    /// The status of the configured `choice`.
    ///
    /// - Parameters:
    ///   - provider: the provider the host set up for `choice`; `nil` when there is none or it could not be set up.
    ///   - limits: the configured usage limits; an OpenAI-compatible endpoint reports their daily request limit.
    /// - Returns: the provider kind, the model's name (never the provider's descriptor name, which contains the
    ///   endpoint's origin), its location, whether it is set up, and the daily request limit.
    static func status(
        of choice: ModelChoice, provider: (any ModelProvider)?, limits: ModelUsageLimits
    ) -> ModelStatusDTO {
        switch choice {
        case .none:
            return ModelStatusDTO(
                provider: "none", name: nil, location: nil, deterministic: false, available: false,
                dailyRequestLimit: nil)
        case .deterministic:
            let descriptor = provider?.descriptor ?? DeterministicProvider().descriptor
            return ModelStatusDTO(
                provider: "deterministic", name: descriptor.name, location: descriptor.location.rawValue,
                deterministic: true, available: provider != nil, dailyRequestLimit: nil)
        case .openAICompatible(let endpoint, let model, _):
            let location =
                provider?.descriptor.location ?? URL(string: endpoint).flatMap { try? ModelEndpoint(base: $0).location }
            let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return ModelStatusDTO(
                provider: "openAICompatible", name: name.isEmpty ? nil : name, location: location?.rawValue,
                deterministic: false, available: provider != nil, dailyRequestLimit: limits.maxRequestsPerDay)
        }
    }
}
