// The settings the Twilio call transport needs: the account, the auth-token reference, the caller ID and time limits.

import LisaSecrets

/// How the Twilio transport places calls (CALL-01). The endpoint is fixed to Twilio's REST API and cannot be changed by
/// configuration. The auth token is only a reference, resolved at every call.
public struct TwilioSettings: Hashable, Sendable {
    /// The Account SID: `AC` and 32 hexadecimal digits. It is the HTTP Basic user name and part of the request path.
    public var accountSID: String
    /// The reference to the account's auth token, the HTTP Basic password.
    public var authTokenSecret: SecretReference
    /// The Twilio number calls come from, in E.164 form.
    public var fromNumber: String
    /// Name resolution, TCP and TLS setup.
    public var connectTimeoutSeconds: Double
    /// The whole exchange. A timeout after the request was sent leaves the outcome unknown, and the call is then
    /// never placed again automatically.
    public var timeoutSeconds: Double

    public init(
        accountSID: String, authTokenSecret: SecretReference, fromNumber: String, connectTimeoutSeconds: Double = 10,
        timeoutSeconds: Double = 30
    ) {
        self.accountSID = accountSID
        self.authTokenSecret = authTokenSecret
        self.fromNumber = fromNumber
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.timeoutSeconds = timeoutSeconds
    }

    /// What prevents placing calls with these settings; empty when they are usable. No entry contains the SID, a
    /// number or a secret.
    public var problems: [String] {
        var found: [String] = []
        if !TwilioFormats.isAccountSID(accountSID) {
            found.append("the Twilio Account SID is not AC followed by 32 hexadecimal digits")
        }
        if !TwilioFormats.isE164(fromNumber) { found.append("the Twilio caller number is not in E.164 form") }
        if !(connectTimeoutSeconds.isFinite && (1...60).contains(connectTimeoutSeconds)) {
            found.append("the Twilio connect timeout is not between 1 and 60 seconds")
        }
        if !(timeoutSeconds.isFinite && (1...120).contains(timeoutSeconds)) {
            found.append("the Twilio request timeout is not between 1 and 120 seconds")
        }
        return found
    }
}
