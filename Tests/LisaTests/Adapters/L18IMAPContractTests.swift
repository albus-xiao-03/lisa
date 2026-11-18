// Adapter tests for L18, provider contracts, for Lisa's mailbox (MAIL-01, MAIL-02, INGEST-01, SEC-02; D-41, D-42): the
// real IMAP connector, through libcurl's implicit TLS and login, reads a synthetic folder from a scripted IMAP server
// on loopback (`openssl s_server` with a certificate from a synthetic authority made at run time). Success reads every
// message with read-only commands only and leaves a cursor the next pass starts after; an authentication failure, a
// command that goes unanswered (timeout), a server limiting commands (throttling, RFC 5530 [LIMIT]) and a dropped
// connection each fail the pass with their own retry class and never with a partial batch; an unverified certificate
// stops the connection before any credential is sent. No real mailbox is contacted.

import Foundation
import LisaCurl
import LisaDomain
import LisaIMAP
import LisaPorts
import LisaSecrets
import Testing

@Suite("L18 — IMAP mailbox contract", .tags(.adapter))
struct L18IMAPContractTests {
    private static let username = "lisa@example.com"
    private static let passwordVariable = "LISA_TEST_IMAP_PASSWORD"
    private static let uidValidity: UInt32 = 4_242
    private static let limits = SyncLimits(maxItems: 50, maxBytes: 1_000_000, timeoutSeconds: 30)

    /// The commands that cannot change a mailbox, its messages or their flags.
    private static let readOnlyCommands = [
        "CAPABILITY", "AUTHENTICATE PLAIN <credentials>", "LOGIN <credentials>", "EXAMINE ", "UID SEARCH UID ",
        "UID FETCH ", "LOGOUT",
    ]

    /// The largest message the connector downloads.
    private static let maxMessageBytes = 2_500
    /// The UID of a message over that limit.
    private static let oversizedUID = 10

    private static func message(_ number: Int) -> ScriptedIMAPServer.Message {
        let body =
            number == oversizedUID
            ? String(repeating: "A long synthetic line that puts this message over the limit.\n", count: 60)
            : "Synthetic message number \(number) for the mailbox contract.\n"
        let mail = SyntheticMail.message(
            subject: "Synthetic note \(number)", messageID: "<l18-imap-\(number)@example.com>", body: body)
        return ScriptedIMAPServer.Message(uid: UInt32(number), data: mail.data)
    }

    private static func folder(_ uids: [Int], password: String) -> ScriptedIMAPServer.Folder {
        ScriptedIMAPServer.Folder(
            username: username, password: password, uidValidity: uidValidity, messages: uids.map(message))
    }

    /// The connector for `server`, trusting `authority` and holding `password` in its secret store.
    private func connector(
        port: Int, authority: URL, password: String, commandTimeoutSeconds: Int = 10
    ) -> IMAPMailboxConnector {
        let settings = IMAPMailboxSettings(
            host: "127.0.0.1", port: port, security: .implicitTLS, username: Self.username,
            password: .environment(Self.passwordVariable), addresses: .allowLocalNetworks,
            maxMessageBytes: Self.maxMessageBytes, connectTimeoutSeconds: 5,
            commandTimeoutSeconds: commandTimeoutSeconds,
            trustStorePath: authority.path)
        return IMAPMailboxConnector(
            settings: settings, secrets: EnvironmentSecretStore(environment: [Self.passwordVariable: password]),
            clock: TestTime.clock(at: TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)))
    }

    @Test("Fixture success: read-only commands, an oversized message only named, the next pass starting after them")
    func readsTheFolderReadOnly() async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            let password = SyntheticDevice.randomHex(bytes: 16)
            let first = try await ScriptedIMAPServer.with(
                identity: identity, directory: scratch.url, folder: Self.folder([7, 8, 9, 10], password: password)
            ) { server in
                let batch = try await connector(
                    port: server.port, authority: identity.authorityFile, password: password
                )
                .fetch(cursor: nil, limits: Self.limits)
                #expect(try await server.waitUntilClosed())
                let record = server.received
                #expect(record.authenticatedUser == Self.username)
                #expect(record.refusedCommands.isEmpty, "\(record.refusedCommands)")
                #expect(
                    record.commands.allSatisfy { command in Self.readOnlyCommands.contains { command.hasPrefix($0) } },
                    "\(record.commands)")
                #expect(record.commands.contains { $0.hasPrefix("EXAMINE ") })
                // Only the messages within the limit are downloaded.
                #expect(record.commands.contains("UID FETCH 7:9 (UID RFC822.SIZE BODY.PEEK[])"), "\(record.commands)")
                #expect(record.commands.last == "LOGOUT")
                return batch
            }
            #expect(first.items.map(\.externalID) == ["imap:4242:7", "imap:4242:8", "imap:4242:9"])
            #expect(first.items.map(\.data) == [7, 8, 9].map { Self.message($0).data })
            #expect(first.items.allSatisfy { $0.kind == .email })
            #expect(!first.isCompleteSnapshot)
            #expect(!first.hasMore)
            let oversized = Self.message(Self.oversizedUID).data.count
            #expect(
                first.capabilityNotes == [
                    "message UID 10 is \(oversized) bytes, larger than the \(Self.maxMessageBytes)-byte limit; it was not"
                        + " downloaded and stays in the mailbox"
                ])
            // The cursor moves past the oversized message, which stays named rather than retried.
            #expect(first.nextCursor == "imap-v1:4242:10:INBOX")

            // A later pass from the stored cursor reads only the message that arrived since.
            let second = try await ScriptedIMAPServer.with(
                identity: identity, directory: scratch.url, folder: Self.folder([7, 8, 9, 10, 12], password: password)
            ) { server in
                try await connector(port: server.port, authority: identity.authorityFile, password: password)
                    .fetch(cursor: first.nextCursor, limits: Self.limits)
            }
            #expect(second.items.map(\.externalID) == ["imap:4242:12"])
            #expect(second.nextCursor == "imap-v1:4242:12:INBOX")
        }
    }

    /// One way a pass fails.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        var name: String
        var interference: [ScriptedIMAPServer.Command: ScriptedIMAPServer.Interference] = [:]
        /// The connector holds a password the server does not accept.
        var wrongPassword = false
        /// The connector trusts another synthetic authority than the one that signed the server's certificate.
        var otherAuthority = false
        var expected: SourceErrorClass
        /// Short only where the timeout is the point, so a busy machine cannot turn another case into one.
        var commandTimeoutSeconds = 10
        var testDescription: String { name }
    }

    static let failureCases: [FailureCase] = [
        FailureCase(name: "authentication failure", wrongPassword: true, expected: .authentication),
        FailureCase(
            name: "timeout: the message transfer goes unanswered", interference: [.uidFetchMessages: .silence],
            expected: .timeout, commandTimeoutSeconds: 2),
        FailureCase(
            name: "throttling: the server limits commands",
            interference: [.uidSearch: .refuse("NO [LIMIT] Too many commands, try again later")],
            expected: .rateLimited),
        FailureCase(
            name: "the connection drops during the transfer", interference: [.uidFetchMessages: .disconnect],
            expected: .network),
        FailureCase(name: "the certificate does not verify", otherAuthority: true, expected: .authentication),
    ]

    @Test(
        "Each failure fails the whole pass with its own retry class and never leaks the password",
        arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            let password = SyntheticDevice.randomHex(bytes: 16)
            let trusted =
                failure.otherAuthority
                ? try await SyntheticTLSIdentity.generate(in: scratch.path("other-tls")).authorityFile
                : identity.authorityFile
            let configured = failure.wrongPassword ? SyntheticDevice.randomHex(bytes: 16) : password
            try await ScriptedIMAPServer.with(
                identity: identity, directory: scratch.url, folder: Self.folder([7, 8, 9], password: password),
                interference: failure.interference
            ) { server in
                let connector = connector(
                    port: server.port, authority: trusted, password: configured,
                    commandTimeoutSeconds: failure.commandTimeoutSeconds)
                let error = try await #require(throws: ConnectorError.self) {
                    try await connector.fetch(cursor: nil, limits: Self.limits)
                }
                #expect(error.errorClass == failure.expected, "\(error)")
                #expect(error.errorClass.isRetryable == (failure.expected != .authentication))
                #expect(!error.summary.contains(password) && !error.summary.contains(configured))
                let record = server.received
                if failure.wrongPassword {
                    #expect(record.loginRefused)
                    #expect(!record.commands.contains { $0.hasPrefix("EXAMINE") })
                }
                if failure.otherAuthority {
                    // TLS failed before libcurl's first command, so no credential reached the server.
                    #expect(record.commands.isEmpty)
                    #expect(record.authenticatedUser == nil && !record.loginRefused)
                }
                #expect(record.refusedCommands.isEmpty, "\(record.refusedCommands)")
            }
        }
    }
}
