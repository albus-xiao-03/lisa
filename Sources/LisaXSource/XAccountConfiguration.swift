// The configuration of one X account source: the account's numeric user ID and its bearer-token reference.

import LisaPorts
import LisaSecrets

/// One selected X account, read through the official X API v2 with the app-only bearer token of the owner's X
/// developer app (NEWS-02). The token is only referenced here; it is resolved from the secret store at each fetch.
public struct XAccountConfiguration: Hashable, Sendable {
    /// The account's numeric user ID.
    public var userID: String
    /// Where the app-only bearer token is kept, such as `env:LISA_X_BEARER_TOKEN`.
    public var bearerToken: SecretReference

    public init(userID: String, bearerToken: SecretReference) {
        self.userID = userID
        self.bearerToken = bearerToken
    }

    /// Checks the configuration without contacting X.
    func validate() throws(ConnectorError) {
        guard XIdentifier.isValid(userID) else {
            throw ConnectorError(.configuration, "the X user ID must be 1 to 19 digits")
        }
    }
}
