// The kinds of logical action that can reach a person, a device, an account or a provider (plan §10.8 "The action
// ledger").

/// What a logical action is.
public enum VerifyActionKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// A real message; observable by its `Message-ID` in Sent (absence proves nothing).
    case email
    /// A push; observable only by the device's receipt report and the owner (APNs offers no lookup).
    case push
    /// A model request; observable by Lisa's accounting record and the provider's request ID when the answer arrived.
    case modelRequest = "model-request"
    /// A Twilio call; observable in the call log for the account, number and window, which also gives the count.
    case call
}
