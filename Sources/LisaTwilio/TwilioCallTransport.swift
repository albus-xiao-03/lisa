// The production call transport (CALL-01): asks Twilio Programmable Voice to call the given number and speak the
// message with inline TwiML, resolving the auth token at every call.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime

/// Places calls through Twilio's Calls resource. It calls exactly the number it is given: whether a call is allowed,
/// and to which approved number, is decided by the call gate before this transport is reached. Results never contain
/// the auth token, phone numbers or the spoken text.
public struct TwilioCallTransport: CallTransport {
    public let mode = DeliveryMode.live
    public let settings: TwilioSettings
    private let secrets: any SecretStore
    private let http: any HTTPClient
    private let clock: any WallClock

    /// - Parameters:
    ///   - settings: the account and caller number; checked again at every call.
    ///   - secrets: resolves `settings.authTokenSecret` when a call is placed.
    ///   - http: the HTTP client; in production LisaCurl's `CurlHTTPClient` with the system trust store.
    ///   - clock: interprets `Retry-After`.
    public init(settings: TwilioSettings, secrets: any SecretStore, http: any HTTPClient, clock: any WallClock) {
        self.settings = settings
        self.secrets = secrets
        self.http = http
        self.clock = clock
    }

    public func place(_ call: CallRequest) async -> TransportResult {
        let problems = settings.problems
        guard problems.isEmpty else {
            return TwilioResultClassification.refused(
                "the Twilio transport is misconfigured: " + problems.joined(separator: "; "))
        }
        guard TwilioFormats.isE164(call.to) else {
            return TwilioResultClassification.refused(
                "the call was not placed: the destination is not an E.164 phone number")
        }
        guard let twiml = TwiMLSpeech.document(speaking: call.spokenText) else {
            return TwilioResultClassification.refused("the call was not placed: there is no text to speak")
        }
        let token: Sensitive<String>
        do {
            token = try secrets.secret(for: settings.authTokenSecret)
        } catch {
            return TwilioResultClassification.result(forSecretError: error)
        }
        guard
            let request = TwilioCallRequestBuilder.request(
                settings: settings, to: call.to, twiml: twiml, authToken: token)
        else { return TwilioResultClassification.refused("the call request could not be built") }
        do {
            let response = try await http.send(request)
            return TwilioResultClassification.result(for: response, now: clock.now())
        } catch {
            return TwilioResultClassification.result(for: error)
        }
    }
}
