// The model configuration as the settings screen shows it, from health's `model`: which model, where it runs,
// whether it is in use, and its daily limit.

import Foundation
import LisaAPIContract

/// The host's model configuration (UI-01: model configuration, MODEL-01) from health's `model`, in plain words. The
/// host reports no endpoint address or credential. Rule-based results are never presented as a language model's.
public struct ModelConfigurationSummary: Hashable, Sendable {
    /// Whether the host reported its model configuration; older hosts do not.
    public var isReported: Bool
    /// The host's provider: `none`, `deterministic` or `openAICompatible`.
    public var provider: String?
    /// The model's name.
    public var name: String?
    /// The host's location: `inProcess`, `localNetwork` or `remote`.
    public var location: String?
    /// Whether results come from fixed rules rather than a model.
    public var isDeterministic: Bool
    /// Whether the host set the provider up.
    public var isAvailable: Bool
    /// The daily limit of model requests, when requests are counted.
    public var dailyRequestLimit: Int?
    /// What is configured, such as "Rule-based extraction (no language model)".
    public var title: String
    /// Where it runs, in words; `nil` when unknown.
    public var locationText: String?
    /// Whether it is in use, and what happens when it is not.
    public var statusMessage: String
    /// The daily limit in words; `nil` when requests are not counted.
    public var limitText: String?

    /// The summary of `model`, or of a host that does not report it when `nil`.
    public init(_ model: ModelStatusDTO?) {
        isReported = model != nil
        provider = model?.provider
        name = model?.name
        location = model?.location
        isDeterministic = model?.deterministic ?? false
        isAvailable = model?.available ?? false
        dailyRequestLimit = model?.dailyRequestLimit
        title =
            switch model?.provider {
            case nil: "Not reported"
            case "none": "No model"
            case "deterministic": "Rule-based extraction (no language model)"
            case "openAICompatible": "\(model?.name ?? "A model") through an OpenAI-compatible endpoint"
            case let other?: other
            }
        locationText =
            switch model?.location {
            case "inProcess": "Runs inside Lisa; nothing is sent anywhere."
            case "localNetwork": "Runs on this computer or your local network."
            case "remote": "Runs on a remote service."
            default: nil
            }
        statusMessage =
            if model == nil {
                "This Lisa host does not report its model configuration."
            } else if model?.provider == "none" {
                "No model is configured. Items that need one wait until a model is set up."
            } else if !isAvailable {
                "The configured model can't be used, so items that need it wait. The host's diagnostics say why."
            } else if isDeterministic {
                "In use. Its results come from fixed rules, not from a language model."
            } else {
                "In use."
            }
        limitText = dailyRequestLimit.map { "Up to \($0) model requests a day." }
    }
}
