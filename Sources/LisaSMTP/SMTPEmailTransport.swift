// The production email transport (EMAIL-01): composes each envelope with LisaMIME and submits it with libcurl over
// implicit TLS or required STARTTLS, resolving the password at every send.

import Foundation
import LisaCurl
import LisaDomain
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime

/// Sends email through Lisa's SMTP submission server. It sends exactly the envelope it is given: the outbox decides
/// whether a message may be sent and to which approved addresses, and this transport never adds, drops or rewrites a
/// recipient. Results never contain the password, the addresses or the message text.
public struct SMTPEmailTransport: EmailTransport {
    public let mode = DeliveryMode.live
    public let settings: SMTPSettings
    private let secrets: any SecretStore
    private let clock: any WallClock

    /// - Parameters:
    ///   - settings: the server, account and limits; checked again at every send.
    ///   - secrets: resolves `settings.passwordSecret` when a message is sent.
    ///   - clock: dates each message.
    public init(settings: SMTPSettings, secrets: any SecretStore, clock: any WallClock) {
        self.settings = settings
        self.secrets = secrets
        self.clock = clock
    }

    public func send(_ envelope: EmailEnvelope) async -> TransportResult {
        let problems = settings.problems
        guard problems.isEmpty else { return SMTPResultClassification.misconfigured(problems) }
        let submission: SMTPSubmission
        switch SMTPMessageComposition.compose(envelope, date: clock.now(), maxMessageBytes: settings.maxMessageBytes) {
        case .success(let composed): submission = composed
        case .failure(let error): return SMTPResultClassification.result(for: error)
        }
        let password: Sensitive<String>
        do {
            password = try secrets.secret(for: settings.passwordSecret)
        } catch {
            return SMTPResultClassification.result(forSecretError: error, reference: settings.passwordSecret)
        }
        let message = CurlSMTPMessage(
            heloName: submission.heloName, from: submission.envelopeFrom, recipients: submission.recipients,
            data: submission.data, timeoutSeconds: settings.totalTimeoutSeconds)
        do {
            // libcurl reports success only after the server's 250 reply to the end of the message.
            _ = try await CurlSMTPSubmission.submit(
                message, server: settings.server, username: settings.username, password: password.revealed)
            return .accepted(providerReference: submission.messageID)
        } catch {
            return SMTPResultClassification.result(for: error)
        }
    }
}
