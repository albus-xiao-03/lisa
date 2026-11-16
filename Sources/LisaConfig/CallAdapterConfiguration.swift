// The `calls` section: the Twilio Programmable Voice adapter, with its auth token kept as a secret reference.

import LisaSecrets

/// The outbound call adapter (CALL-01), Twilio Programmable Voice. Configuring it places no call: real calls also
/// need `delivery.callsEnabled`, `delivery.approvedPhoneNumber` and `delivery.modes.call` set to `live`, and every
/// call must pass the call gate.
public struct CallAdapterConfiguration: Hashable, Sendable {
    /// The Twilio Account SID: `AC` and 32 hexadecimal digits.
    public let accountSID: String
    /// The reference to the Twilio auth token.
    public let authTokenSecret: SecretReference
    /// The Twilio number calls come from, in E.164 form.
    public let fromNumber: String

    static func decode(_ section: ConfigSection) -> CallAdapterConfiguration? {
        defer { section.finish() }
        let accountSID = section.requiredValidated(
            "accountSID", maxLength: 34, fix: "copy the Account SID from the Twilio console", Self.accountSID)
        let authTokenSecret = section.requiredSecret(
            "authTokenSecret", fix: "reference the Twilio auth token, such as env:LISA_TWILIO_AUTH_TOKEN")
        let fromNumber = section.requiredValidated(
            "fromNumber", maxLength: 16, fix: "the Twilio number calls come from, such as +15555550199",
            DeliveryConfiguration.phoneNumber)
        guard let accountSID, let authTokenSecret, let fromNumber else { return nil }
        return CallAdapterConfiguration(
            accountSID: accountSID, authTokenSecret: authTokenSecret, fromNumber: fromNumber)
    }

    private static func accountSID(_ text: String) -> Result<String, ValueRefusal> {
        let digits = text.dropFirst(2)
        let valid =
            text.hasPrefix("AC") && digits.utf8.count == 32
            && digits.unicodeScalars.allSatisfy(\.properties.isASCIIHexDigit)
        return valid
            ? .success(text) : .failure(ValueRefusal("must be a Twilio Account SID: AC and 32 hexadecimal digits"))
    }
}
