// APNs provider settings: the Team ID, the signing credentials of each allowed environment, and the allowed topics.

import LisaDomain
import LisaSecrets

/// The token-signing credentials of one APNs environment.
public struct APNsSigningCredentials: Hashable, Sendable {
    /// The 10-character Key ID of the APNs authentication key, sent as the provider token's `kid`.
    public var keyID: String
    /// Where the PEM-encoded `.p8` signing key is kept. It is resolved each time a provider token is signed, never
    /// when the transport is created, so a missing key is a classified failure of the push that needs it.
    public var signingKey: SecretReference

    public init(keyID: String, signingKey: SecretReference) {
        self.keyID = keyID
        self.signingKey = signingKey
    }
}

/// The APNs provider configuration (plan §6.2). Everything here is non-secret except the signing key, which is only
/// referenced. Endpoints are fixed per environment (``APNsEndpoint``) and are deliberately not configurable.
///
/// Apple's team-scoped keys are restricted to either the sandbox or the production environment (S11), so each
/// environment carries its own credentials. A key that works in both environments may be given for both.
public struct APNsSettings: Hashable, Sendable {
    /// The most topics accepted, as an input bound.
    public static let maxTopics = 100

    /// The 10-character Team ID, sent as the provider token's `iss`.
    public var teamID: String
    /// The credentials of each environment Lisa may push to. An environment without credentials is not allowed.
    public var credentials: [APNsEnvironment: APNsSigningCredentials]
    /// The app bundle identifiers Lisa may push to. Alert pushes use the app's bundle ID as the topic (S10).
    public var allowedTopics: Set<String>

    /// Settings that use one key for every allowed environment.
    public init(
        teamID: String, keyID: String, signingKey: SecretReference, allowedTopics: Set<String>,
        allowedEnvironments: Set<APNsEnvironment>
    ) {
        let shared = APNsSigningCredentials(keyID: keyID, signingKey: signingKey)
        var credentials: [APNsEnvironment: APNsSigningCredentials] = [:]
        for environment in allowedEnvironments { credentials[environment] = shared }
        self.init(teamID: teamID, credentials: credentials, allowedTopics: allowedTopics)
    }

    /// Settings with separate credentials per environment, for Apple's environment-specific keys.
    public init(teamID: String, credentials: [APNsEnvironment: APNsSigningCredentials], allowedTopics: Set<String>) {
        self.teamID = teamID
        self.credentials = credentials
        self.allowedTopics = allowedTopics
    }

    /// The environments Lisa may push to.
    public var allowedEnvironments: Set<APNsEnvironment> { Set(credentials.keys) }

    /// Checks the identifiers and topics; throws the first problem found. The signing key is not read here.
    public func validate() throws(APNsConfigurationError) {
        guard Self.isTenCharacterIdentifier(teamID) else { throw .invalidTeamID }
        guard !credentials.isEmpty else { throw .noEnvironments }
        for environment in APNsEnvironment.allCases {
            guard let entry = credentials[environment] else { continue }
            guard Self.isTenCharacterIdentifier(entry.keyID) else { throw .invalidKeyID(environment) }
        }
        guard !allowedTopics.isEmpty else { throw .noTopics }
        guard allowedTopics.count <= Self.maxTopics else { throw .tooManyTopics(limit: Self.maxTopics) }
        guard allowedTopics.allSatisfy(Self.isBundleIdentifier) else { throw .invalidTopic }
    }

    /// Exactly ten ASCII letters and digits: the form of Apple's Team IDs and Key IDs ("10-character", S11). The
    /// restriction to letters and digits also keeps both safe to place in the token's JSON without escaping.
    static func isTenCharacterIdentifier(_ text: String) -> Bool {
        text.utf8.count == 10 && text.utf8.allSatisfy(isASCIIAlphanumeric)
    }

    /// A header-safe bundle identifier: dot-separated, non-empty labels of ASCII letters, digits and hyphens, at most
    /// 255 bytes (an input bound).
    static func isBundleIdentifier(_ text: String) -> Bool {
        guard (1...255).contains(text.utf8.count) else { return false }
        return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.utf8.allSatisfy { isASCIIAlphanumeric($0) || $0 == 0x2D }
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }
}
