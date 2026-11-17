// The HTTP request that creates one call through Twilio's Calls resource: the fixed endpoint, form fields with inline
// TwiML, HTTP Basic authentication as a sensitive header, and the network limits.

import Foundation
import LisaHTTP
import LisaRedaction

/// Builds `POST /2010-04-01/Accounts/{AccountSid}/Calls.json` requests.
enum TwilioCallRequestBuilder {
    /// Twilio's REST API. It is fixed, so configuration can never send a call request or the credentials elsewhere.
    static let apiOrigin = "https://api.twilio.com"
    /// A created call's JSON is a few kilobytes; anything beyond this is not a Calls-resource response.
    static let maxResponseBytes = 65_536

    /// The Calls resource of `accountSID`, or `nil` unless it is a valid Account SID (it becomes part of the path).
    static func endpoint(accountSID: String) -> URL? {
        guard TwilioFormats.isAccountSID(accountSID) else { return nil }
        return URL(string: "\(apiOrigin)/2010-04-01/Accounts/\(accountSID)/Calls.json")
    }

    /// The request that asks Twilio to call `destination` and follow `twiml`: form-encoded `To`, `From` and `Twiml`
    /// (never `Url`), JSON responses, public addresses only, and no redirects.
    static func request(settings: TwilioSettings, to destination: String, twiml: String, authToken: Sensitive<String>)
        -> HTTPRequest?
    {
        guard let url = endpoint(accountSID: settings.accountSID) else { return nil }
        let credentials = Data("\(settings.accountSID):\(authToken.revealed)".utf8).base64EncodedString()
        let body = FormURLEncoding.body([
            (name: "To", value: destination), (name: "From", value: settings.fromNumber), (name: "Twiml", value: twiml),
        ])
        return HTTPRequest(
            method: "POST", url: url,
            headers: [
                HTTPHeader("Authorization", "Basic \(credentials)", sensitive: true),
                HTTPHeader("Content-Type", "application/x-www-form-urlencoded"),
                HTTPHeader("Accept", "application/json"),
            ],
            body: body, timeoutSeconds: settings.timeoutSeconds, connectTimeoutSeconds: settings.connectTimeoutSeconds,
            maxResponseBytes: maxResponseBytes, version: .any, redirects: .none, addresses: .publicOnly)
    }
}
