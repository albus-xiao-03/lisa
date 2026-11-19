// Adapter tests for L18, provider contracts, for outbound email (EMAIL-01, REM-03, SEC-01; D-41, D-42): the real SMTP
// transport composes each envelope with LisaMIME and submits it through libcurl's implicit TLS to a scripted SMTP
// server on loopback (`openssl s_server` with a certificate from a synthetic authority made at run time). Success
// delivers exactly the envelope's sender, recipient and text under the configured account; an authentication failure
// is a rejection that is never retried; a server deferring the sender (throttling) is a temporary refusal; and a
// timeout is "not sent" while nothing was handed over, but "unknown" once the whole message was, so it is never
// resent automatically. Nothing is relayed anywhere and no real account is used.

import Foundation
import LisaMIME
import LisaPorts
import LisaSMTP
import LisaSecrets
import Testing

@Suite("L18 — SMTP submission contract", .tags(.adapter))
struct L18SMTPContractTests {
    private static let username = "lisa@example.com"
    private static let passwordVariable = "LISA_TEST_SMTP_PASSWORD"

    private static let envelope = EmailEnvelope(
        from: TestHost.lisaAddress, fromName: "Lisa", to: [TestHost.ownerAddress], subject: "Synthetic reminder",
        textBody: "Your synthetic filing is due at 10:00.\n.A line that starts with a dot.",
        messageID: "<l18-smtp-0001@example.com>")

    private func transport(
        port: Int, authority: URL, password: String, responseTimeoutSeconds: Int = 10
    ) -> SMTPEmailTransport {
        let settings = SMTPSettings(
            host: "127.0.0.1", port: port, security: .implicitTLS, username: Self.username,
            passwordSecret: .environment(Self.passwordVariable),
            addresses: SMTPSettings.addressPolicy(forHost: "127.0.0.1"),
            connectTimeoutSeconds: 5, responseTimeoutSeconds: responseTimeoutSeconds, totalTimeoutSeconds: 30,
            trustStorePath: authority.path)
        return SMTPEmailTransport(
            settings: settings, secrets: EnvironmentSecretStore(environment: [Self.passwordVariable: password]),
            clock: TestTime.clock(at: TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)))
    }

    @Test("Fixture success: the envelope's sender, recipient and text arrive under the configured account")
    func submitsTheEnvelope() async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            let password = SyntheticDevice.randomHex(bytes: 16)
            try await ScriptedSMTPServer.with(
                identity: identity, directory: scratch.url,
                account: ScriptedSMTPServer.Account(username: Self.username, password: password)
            ) { server in
                let result = await transport(port: server.port, authority: identity.authorityFile, password: password)
                    .send(Self.envelope)
                #expect(result == .accepted(providerReference: "<l18-smtp-0001@example.com>"), "\(result)")
                let record = server.received
                #expect(record.authenticatedUser == Self.username)
                #expect(record.heloName == "example.com")
                #expect(record.mailFrom == TestHost.lisaAddress)
                #expect(record.recipients == [TestHost.ownerAddress])
                #expect(record.messages.count == 1)
                let mail = ParsedMail.from(try MIMEParser.parse(try #require(record.messages.first))) { $0 }
                #expect(mail.subject == "Synthetic reminder")
                #expect(mail.messageID == "l18-smtp-0001@example.com")
                #expect(mail.from?.address == TestHost.lisaAddress)
                #expect(mail.to.map(\.address) == [TestHost.ownerAddress])
                #expect(mail.text.contains("Your synthetic filing is due at 10:00."))
                #expect(mail.text.contains(".A line that starts with a dot."))
                #expect(!record.commands.contains { $0.contains(password) })
            }
        }
    }

    /// How a submission is answered, and what the transport must make of it.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        enum Expected: Sendable {
            case rejected
            case temporarilyUnavailable
            case notSent
            case unknown
        }

        var name: String
        var interference: [ScriptedSMTPServer.Stage: ScriptedSMTPServer.Interference] = [:]
        var wrongPassword = false
        var expected: Expected
        /// Whether the server received the whole message.
        var messageReceived: Bool
        /// Short only where the timeout is the point, so a busy machine cannot turn another case into one.
        var responseTimeoutSeconds = 10
        var testDescription: String { name }

        func matches(_ result: TransportResult) -> Bool {
            switch (expected, result) {
            case (.rejected, .rejected(_, let invalidatesRecipient, _)): !invalidatesRecipient
            case (.temporarilyUnavailable, .temporarilyUnavailable), (.notSent, .notSent), (.unknown, .unknown): true
            default: false
            }
        }
    }

    static let failureCases: [FailureCase] = [
        FailureCase(
            name: "authentication failure: rejected, never retried", wrongPassword: true, expected: .rejected,
            messageReceived: false),
        FailureCase(
            name: "throttling: the server defers the sender",
            interference: [.mailFrom: .reply("451 4.7.1 Too many messages, try again later")],
            expected: .temporarilyUnavailable, messageReceived: false),
        FailureCase(
            name: "timeout before the message was handed over: not sent", interference: [.mailFrom: .silence],
            expected: .notSent, messageReceived: false, responseTimeoutSeconds: 2),
        FailureCase(
            name: "timeout after the whole message was handed over: unknown", interference: [.endOfData: .silence],
            expected: .unknown, messageReceived: true, responseTimeoutSeconds: 2),
    ]

    @Test("Each failure gets the result that decides whether the outbox may send again", arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            let password = SyntheticDevice.randomHex(bytes: 16)
            let configured = failure.wrongPassword ? SyntheticDevice.randomHex(bytes: 16) : password
            try await ScriptedSMTPServer.with(
                identity: identity, directory: scratch.url,
                account: ScriptedSMTPServer.Account(username: Self.username, password: password),
                interference: failure.interference
            ) { server in
                let transport = transport(
                    port: server.port, authority: identity.authorityFile, password: configured,
                    responseTimeoutSeconds: failure.responseTimeoutSeconds)
                let result = await transport.send(Self.envelope)
                #expect(failure.matches(result), "\(result)")
                #expect(!"\(result)".contains(password) && !"\(result)".contains(configured))
                #expect(!"\(result)".contains(TestHost.ownerAddress))
                let record = server.received
                #expect(record.messages.count == (failure.messageReceived ? 1 : 0))
                if failure.wrongPassword {
                    #expect(record.authenticationRefused)
                    #expect(record.mailFrom == nil)
                }
            }
        }
    }
}
