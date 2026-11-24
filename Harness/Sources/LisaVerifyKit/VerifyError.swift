// Why a harness command refused or failed (plan §10.8). Messages name the input and never contain secrets.

/// A refusal or failure of the owner-verification harness.
public enum VerifyError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidRunID(String)
    case invalidCaseID(String)
    case unknownCase(String)
    case runNotFound(String)
    case store(String)
    case ledger(String)
    /// A live run's logical actions aren't covered by a confirmation (`--confirm-real-actions`).
    case confirmationRequired(String)
    /// `authorize-retry` without the exact typed phrase, or for an action that isn't ambiguous.
    case retryNotAuthorized(String)
    case invalidInput(String)

    public var description: String {
        switch self {
        case .invalidRunID(let text): "Not a run ID: \(text) (expected run-YYYYMMDDTHHMMSSZ-<6 base32 characters>)"
        case .invalidCaseID(let text): "Not a case ID: \(text) (expected OV-<AREA>[-<PROVIDER>…]-<NN>)"
        case .unknownCase(let text): "No case \(text) in the catalogue"
        case .runNotFound(let text): "No run \(text) in the run store"
        case .store(let text): "Run store: \(text)"
        case .ledger(let text): "Action ledger: \(text)"
        case .confirmationRequired(let text): "Real actions need confirmation: \(text)"
        case .retryNotAuthorized(let text): "Retry not authorized: \(text)"
        case .invalidInput(let text): text
        }
    }
}
