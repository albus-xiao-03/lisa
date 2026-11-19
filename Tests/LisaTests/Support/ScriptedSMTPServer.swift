// Test-only controlled substitute (plan §10): a scripted SMTP submission server for one connection on 127.0.0.1, with
// implicit TLS from `openssl s_server` and a synthetic certificate (ScriptedDialog). It answers EHLO, AUTH PLAIN
// (with or without an initial response) against synthetic credentials, MAIL FROM, RCPT TO, DATA and QUIT, and keeps
// each submitted message. The test can replace the reply at one stage, leave it unanswered, or drop the connection
// there. Credentials are checked but never recorded. Nothing is relayed anywhere. Used by the SMTP contract suite
// (L18).

import Foundation
import Synchronization

/// A scripted submission server. It is never presented as a real provider; it only answers the commands it receives.
final class ScriptedSMTPServer: Sendable {
    /// The stages a test can interfere with.
    enum Stage: Hashable, Sendable {
        case authentication
        case mailFrom
        case recipient
        case data
        /// After the whole message, when the server would accept it.
        case endOfData
    }

    /// How a stage is answered instead of normally.
    enum Interference: Sendable {
        /// This reply line, such as `451 4.7.1 Too many messages, try again later`.
        case reply(String)
        /// No reply at all: the client's own time limit ends the exchange.
        case silence
        /// The connection is dropped without a reply.
        case disconnect
    }

    /// What the client did, without its credentials.
    struct Record: Sendable {
        /// Every command, credentials replaced by `<credentials>`; message lines are not commands.
        var commands: [String] = []
        var heloName: String?
        var authenticatedUser: String?
        var authenticationRefused = false
        var mailFrom: String?
        var recipients: [String] = []
        /// Every message received in full, with dot-stuffing removed.
        var messages: [Data] = []
    }

    /// The account the server accepts.
    struct Account: Sendable {
        var username: String
        var password: String
    }

    private final class Shared: Sendable {
        let record = Mutex(Record())
    }

    private let dialog: ScriptedDialog
    private let shared: Shared

    /// The port on 127.0.0.1.
    var port: Int { dialog.port }

    /// What the client has done so far.
    var received: Record { shared.record.withLock { $0 } }

    private init(dialog: ScriptedDialog, shared: Shared) {
        self.dialog = dialog
        self.shared = shared
    }

    /// Starts a server for one connection that accepts `account`, with `interference` applied at its stages.
    static func start(
        identity: SyntheticTLSIdentity, directory: URL, account: Account, interference: [Stage: Interference] = [:]
    ) async throws -> ScriptedSMTPServer {
        let shared = Shared()
        let dialog = try await ScriptedDialog.start(
            identity: identity, directory: directory, greeting: "220 smtp.example.invalid ESMTP Synthetic server\r\n"
        ) { connection, shouldStop in
            var session = Session(account: account, interference: interference, shared: shared, connection: connection)
            session.run(shouldStop: shouldStop)
        }
        return ScriptedSMTPServer(dialog: dialog, shared: shared)
    }

    /// Ends the connection, if the client has not, and stops the server.
    func stop() async {
        await dialog.stop()
    }

    /// Runs `body` with a started server and stops it afterwards, whether `body` returns or throws.
    static func with<Result>(
        identity: SyntheticTLSIdentity, directory: URL, account: Account, interference: [Stage: Interference] = [:],
        _ body: (ScriptedSMTPServer) async throws -> Result
    ) async throws -> Result {
        let server = try await start(
            identity: identity, directory: directory, account: account, interference: interference)
        do {
            let result = try await body(server)
            await server.stop()
            return result
        } catch {
            await server.stop()
            throw error
        }
    }

    /// The conversation, on the dialog thread.
    private struct Session {
        let account: Account
        let interference: [Stage: Interference]
        let shared: Shared
        let connection: OpenSSLServerProcess
        var awaitingCredentials = false
        var message: [UInt8]?

        mutating func run(shouldStop: () -> Bool) {
            while let line = connection.nextLine(shouldStop: shouldStop) {
                if message != nil {
                    guard receive(line) else { return }
                } else if awaitingCredentials {
                    awaitingCredentials = false
                    authenticate(String(decoding: line, as: UTF8.self))
                } else if !handle(String(decoding: line, as: UTF8.self)) {
                    return
                }
            }
        }

        /// Handles one command; returns false when the connection was dropped.
        mutating func handle(_ line: String) -> Bool {
            let upper = line.uppercased()
            let verb = upper.split(separator: " ").first.map(String.init) ?? ""
            switch verb {
            case "EHLO", "HELO":
                note(line)
                shared.record.withLock { $0.heloName = String(line.dropFirst(5)) }
                connection.send(
                    "250-smtp.example.invalid Synthetic server\r\n250-AUTH PLAIN\r\n250-8BITMIME\r\n250 SIZE 10485760\r\n"
                )
            case "AUTH":
                note("AUTH PLAIN <credentials>")
                if let outcome = interfere(.authentication) { return outcome }
                let words = line.split(separator: " ").map(String.init)
                guard words.count >= 2, words[1].uppercased() == "PLAIN" else {
                    connection.send("504 5.5.4 Only PLAIN is offered\r\n")
                    return true
                }
                if words.count >= 3 {
                    authenticate(words[2])
                } else {
                    awaitingCredentials = true
                    connection.send("334 \r\n")
                }
            case "MAIL":
                note(line)
                if let outcome = interfere(.mailFrom) { return outcome }
                guard shared.record.withLock({ $0.authenticatedUser != nil }) else {
                    connection.send("530 5.7.0 Authentication required\r\n")
                    return true
                }
                shared.record.withLock { $0.mailFrom = Self.address(in: line) }
                connection.send("250 2.1.0 Sender OK\r\n")
            case "RCPT":
                note(line)
                if let outcome = interfere(.recipient) { return outcome }
                if let address = Self.address(in: line) { shared.record.withLock { $0.recipients.append(address) } }
                connection.send("250 2.1.5 Recipient OK\r\n")
            case "DATA":
                note(line)
                if let outcome = interfere(.data) { return outcome }
                message = []
                connection.send("354 End data with <CR><LF>.<CR><LF>\r\n")
            case "QUIT":
                note(line)
                connection.send("221 2.0.0 Bye\r\n")
            case "RSET", "NOOP":
                note(line)
                connection.send("250 2.0.0 OK\r\n")
            default:
                note(line)
                connection.send("502 5.5.2 Command not recognized\r\n")
            }
            return true
        }

        /// Takes one message line; at the final dot, keeps the message and answers. Returns false when the connection
        /// was dropped.
        private mutating func receive(_ line: [UInt8]) -> Bool {
            guard line != [0x2E] else {
                let data = Data(message ?? [])
                message = nil
                shared.record.withLock { $0.messages.append(data) }
                if let outcome = interfere(.endOfData) { return outcome }
                connection.send("250 2.0.0 OK: queued as SYNTHETIC\r\n")
                return true
            }
            // RFC 5321 §4.5.2: a line that starts with a dot was sent with one more.
            message? += (line.first == 0x2E ? Array(line.dropFirst()) : line) + [0x0D, 0x0A]
            return true
        }

        private func authenticate(_ response: String) {
            let fields = Data(base64Encoded: response).map { data in
                data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            }
            if let fields, fields.count == 3, fields[1] == account.username, fields[2] == account.password {
                shared.record.withLock { $0.authenticatedUser = fields[1] }
                connection.send("235 2.7.0 Authentication successful\r\n")
            } else {
                shared.record.withLock { $0.authenticationRefused = true }
                connection.send("535 5.7.8 Authentication credentials invalid\r\n")
            }
        }

        /// The scripted interference at `stage`: nil when there is none, otherwise whether the dialog continues.
        private func interfere(_ stage: Stage) -> Bool? {
            switch interference[stage] {
            case nil:
                return nil
            case .reply(let reply)?:
                connection.send(reply + "\r\n")
                return true
            case .silence?:
                return true
            case .disconnect?:
                connection.end()
                return false
            }
        }

        private func note(_ command: String) {
            shared.record.withLock { $0.commands.append(command) }
        }

        /// The address between `<` and `>` in a MAIL FROM or RCPT TO command.
        static func address(in line: String) -> String? {
            guard let open = line.firstIndex(of: "<"), let close = line[open...].firstIndex(of: ">") else { return nil }
            return String(line[line.index(after: open)..<close])
        }
    }
}
