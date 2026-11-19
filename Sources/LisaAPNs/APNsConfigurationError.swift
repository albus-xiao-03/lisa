// Why the APNs settings or the transport's composition cannot be used; no case ever carries a secret.

import LisaDomain

/// A configuration problem found before anything is sent.
public enum APNsConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidTeamID
    case invalidKeyID(APNsEnvironment)
    case noEnvironments
    case noTopics
    case tooManyTopics(limit: Int)
    case invalidTopic
    case missingHTTPClient(APNsEnvironment)

    public var description: String {
        switch self {
        case .invalidTeamID:
            "the APNs Team ID must be the 10-character identifier from the Apple Developer account"
        case .invalidKeyID(let environment):
            "the APNs Key ID for \(environment.rawValue) must be the 10-character identifier of the authentication key"
        case .noEnvironments:
            "no APNs environment is enabled"
        case .noTopics:
            "no APNs topic (app bundle identifier) is configured"
        case .tooManyTopics(let limit):
            "more than \(limit) APNs topics are configured"
        case .invalidTopic:
            "an APNs topic is not a valid app bundle identifier"
        case .missingHTTPClient(let environment):
            "no HTTP client was provided for the APNs \(environment.rawValue) environment"
        }
    }
}
