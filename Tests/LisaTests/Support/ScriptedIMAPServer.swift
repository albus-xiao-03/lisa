// Test-only controlled substitute (plan §10): a scripted IMAP4rev1 server for one connection on 127.0.0.1, with
// implicit TLS from `openssl s_server` and a synthetic certificate (ScriptedDialog). It serves one synthetic folder:
// CAPABILITY, AUTHENTICATE PLAIN (with or without an initial response) and LOGIN against synthetic credentials,
// EXAMINE (always [READ-ONLY]), UID SEARCH, UID FETCH of sizes and of BODY.PEEK[] content, and LOGOUT. Any other
// command, and any fetch that would set \Seen, is refused and recorded. The test can make one command fail with a
// scripted reply, go unanswered, or drop the connection. Credentials are checked but never recorded. Used by the IMAP
// contract suite (L18).

import Foundation
import Synchronization

/// A scripted mailbox server. It is never presented as a real provider; it only answers the commands it receives.
final class ScriptedIMAPServer: Sendable {
    /// One message in the folder.
    struct Message: Sendable {
        var uid: UInt32
        var data: Data
    }

    /// The commands a test can interfere with.
    enum Command: Hashable, Sendable {
        case authenticate
        case examine
        case uidSearch
        case uidFetchSizes
        case uidFetchMessages
    }

    /// How a command is answered instead of normally.
    enum Interference: Sendable {
        /// The tagged reply after the tag, such as `NO [LIMIT] Too many commands`.
        case refuse(String)
        /// No reply at all: the client's own time limit ends the command.
        case silence
        /// The connection is dropped without a reply.
        case disconnect
    }

    /// What the client did, without its credentials.
    struct Record: Sendable {
        /// Every command, without its tag; credentials are replaced by `<credentials>`.
        var commands: [String] = []
        /// The user name that authenticated, if any did.
        var authenticatedUser: String?
        /// Whether a login was refused.
        var loginRefused = false
        /// Commands this server refused: any that could change the mailbox or its flags, or that it does not offer.
        var refusedCommands: [String] = []
    }

    /// The folder and account the server serves.
    struct Folder: Sendable {
        var username: String
        var password: String
        var name = "INBOX"
        var uidValidity: UInt32
        var messages: [Message]
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

    /// Starts a server for one connection that serves `folder`, with `interference` applied to its commands.
    static func start(
        identity: SyntheticTLSIdentity, directory: URL, folder: Folder, interference: [Command: Interference] = [:]
    ) async throws -> ScriptedIMAPServer {
        let shared = Shared()
        var sorted = folder
        sorted.messages.sort { $0.uid < $1.uid }
        let served = sorted
        let dialog = try await ScriptedDialog.start(
            identity: identity, directory: directory,
            greeting: "* OK [CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN] Synthetic IMAP server ready\r\n"
        ) { connection, shouldStop in
            var session = Session(folder: served, interference: interference, shared: shared, connection: connection)
            session.run(shouldStop: shouldStop)
        }
        return ScriptedIMAPServer(dialog: dialog, shared: shared)
    }

    /// Ends the connection, if the client has not, and stops the server.
    func stop() async {
        await dialog.stop()
    }

    /// Waits, at most `limit`, until the client has closed the connection.
    func waitUntilClosed(within limit: Duration = .seconds(20)) async throws -> Bool {
        try await dialog.waitUntilFinished(within: limit)
    }

    /// Runs `body` with a started server and stops it afterwards, whether `body` returns or throws.
    static func with<Result>(
        identity: SyntheticTLSIdentity, directory: URL, folder: Folder, interference: [Command: Interference] = [:],
        _ body: (ScriptedIMAPServer) async throws -> Result
    ) async throws -> Result {
        let server = try await start(
            identity: identity, directory: directory, folder: folder, interference: interference)
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
        let folder: Folder
        let interference: [Command: Interference]
        let shared: Shared
        let connection: OpenSSLServerProcess
        /// The tag of an AUTHENTICATE waiting for its SASL response line.
        var pendingAuthentication: String?

        mutating func run(shouldStop: () -> Bool) {
            while let bytes = connection.nextLine(shouldStop: shouldStop) {
                let line = String(decoding: bytes, as: UTF8.self)
                if let tag = pendingAuthentication {
                    pendingAuthentication = nil
                    authenticate(tag: tag, response: line)
                } else if !handle(line) {
                    return
                }
            }
        }

        /// Handles one command line; returns false when the connection was dropped.
        mutating func handle(_ line: String) -> Bool {
            let words = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard words.count >= 2 else {
                note("(malformed)", refused: true)
                send([], tagged: "* BAD a command needs a tag and a name")
                return true
            }
            let tag = words[0]
            let rest = words.count > 2 ? words[2] : ""
            switch words[1].uppercased() {
            case "CAPABILITY":
                note("CAPABILITY")
                send(["* CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN"], tagged: "\(tag) OK CAPABILITY completed")
            case "AUTHENTICATE":
                note("AUTHENTICATE PLAIN <credentials>")
                if let outcome = interfere(.authenticate, tag: tag) { return outcome }
                let arguments = rest.split(separator: " ").map(String.init)
                guard arguments.first?.uppercased() == "PLAIN" else {
                    send([], tagged: "\(tag) NO [CANNOT] only PLAIN is offered")
                    return true
                }
                if arguments.count >= 2 {
                    authenticate(tag: tag, response: arguments[1])
                } else {
                    pendingAuthentication = tag
                    connection.send("+ \r\n")
                }
            case "LOGIN":
                note("LOGIN <credentials>")
                if let outcome = interfere(.authenticate, tag: tag) { return outcome }
                let arguments = rest.split(separator: " ").map { Self.unquoted(String($0)) }
                login(tag: tag, user: arguments.first ?? "", password: arguments.dropFirst().first ?? "")
            case "EXAMINE":
                note("EXAMINE \(rest)")
                if let outcome = interfere(.examine, tag: tag) { return outcome }
                examine(tag: tag, name: Self.unquoted(rest))
            case "UID":
                note("UID \(rest)")
                return uid(tag: tag, rest)
            case "LOGOUT":
                note("LOGOUT")
                send(["* BYE Synthetic IMAP server logging out"], tagged: "\(tag) OK LOGOUT completed")
            default:
                note(words.dropFirst().joined(separator: " "), refused: true)
                send([], tagged: "\(tag) BAD this synthetic server does not offer that command")
            }
            return true
        }

        private func uid(tag: String, _ rest: String) -> Bool {
            let words = rest.split(separator: " ", maxSplits: 2).map(String.init)
            switch (words.first?.uppercased(), words.count) {
            case ("SEARCH", 3) where words[1].uppercased() == "UID":
                if let outcome = interfere(.uidSearch, tag: tag) { return outcome }
                let found = Self.uids(in: words[2], of: folder.messages).map(String.init)
                send(["* SEARCH" + found.map { " \($0)" }.joined()], tagged: "\(tag) OK SEARCH completed")
            case ("FETCH", 3):
                let items = words[2].uppercased()
                if items.contains("BODY[") && !items.contains("BODY.PEEK[") {
                    note("UID \(rest)", refused: true)
                    send([], tagged: "\(tag) BAD this synthetic server never sets \\Seen")
                    return true
                }
                let bodies = items.contains("BODY.PEEK[]")
                if let outcome = interfere(bodies ? .uidFetchMessages : .uidFetchSizes, tag: tag) { return outcome }
                fetch(tag: tag, set: words[1], bodies: bodies)
            default:
                note("UID \(rest)", refused: true)
                send([], tagged: "\(tag) BAD this synthetic server does not offer that command")
            }
            return true
        }

        private func examine(tag: String, name: String) {
            guard name.caseInsensitiveCompare(folder.name) == .orderedSame else {
                send([], tagged: "\(tag) NO [NONEXISTENT] no such folder")
                return
            }
            let next = (folder.messages.last?.uid ?? 0) + 1
            send(
                [
                    "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)", "* \(folder.messages.count) EXISTS",
                    "* 0 RECENT", "* OK [UIDVALIDITY \(folder.uidValidity)] UIDs valid",
                    "* OK [UIDNEXT \(next)] Predicted next UID",
                ], tagged: "\(tag) OK [READ-ONLY] EXAMINE completed")
        }

        private func fetch(tag: String, set: String, bodies: Bool) {
            let wanted = Set(Self.uids(in: set, of: folder.messages))
            for (index, message) in folder.messages.enumerated() where wanted.contains(message.uid) {
                let head = "* \(index + 1) FETCH (UID \(message.uid) RFC822.SIZE \(message.data.count)"
                if bodies {
                    // One write per message, small enough for the pipe to deliver it whole.
                    let literal = Array("\(head) BODY[] {\(message.data.count)}\r\n".utf8) + Array(message.data)
                    connection.send(literal + Array(")\r\n".utf8))
                } else {
                    connection.send("\(head))\r\n")
                }
            }
            send([], tagged: "\(tag) OK FETCH completed")
        }

        private func authenticate(tag: String, response: String) {
            let fields = Data(base64Encoded: response).map { data in
                data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
            }
            guard let fields, fields.count == 3 else {
                send([], tagged: "\(tag) BAD the PLAIN response is malformed")
                return
            }
            login(tag: tag, user: fields[1], password: fields[2])
        }

        private func login(tag: String, user: String, password: String) {
            if user == folder.username && password == folder.password {
                shared.record.withLock { $0.authenticatedUser = user }
                send(["* CAPABILITY IMAP4rev1 SASL-IR AUTH=PLAIN"], tagged: "\(tag) OK authenticated")
            } else {
                shared.record.withLock { $0.loginRefused = true }
                send([], tagged: "\(tag) NO [AUTHENTICATIONFAILED] Invalid credentials")
            }
        }

        /// The scripted interference for `command`: nil when there is none, otherwise whether the dialog continues.
        private func interfere(_ command: Command, tag: String) -> Bool? {
            switch interference[command] {
            case nil:
                return nil
            case .refuse(let reply)?:
                send([], tagged: "\(tag) \(reply)")
                return true
            case .silence?:
                return true
            case .disconnect?:
                connection.end()
                return false
            }
        }

        /// Writes `untagged` lines and the `tagged` completion in one piece. The piece always starts with an untagged
        /// line, so `openssl s_server` can never take its first letter for one of its commands.
        private func send(_ untagged: [String], tagged: String) {
            let lines = (untagged.isEmpty ? ["* OK Synthetic IMAP server"] : untagged) + [tagged]
            connection.send(lines.map { $0 + "\r\n" }.joined())
        }

        private func note(_ command: String, refused: Bool = false) {
            shared.record.withLock { record in
                record.commands.append(command)
                if refused { record.refusedCommands.append(command) }
            }
        }

        /// The UIDs of `messages` in an IMAP set such as `1:3,7` or `4:*`, where `*` is the highest UID in use and a
        /// range covers both of its ends in either order (RFC 9051 §9, `seq-range`).
        static func uids(in set: String, of messages: [Message]) -> [UInt32] {
            let highest = messages.last?.uid ?? 0
            var wanted: Set<UInt32> = []
            for item in set.split(separator: ",") {
                let ends = item.split(separator: ":").map { $0 == "*" ? highest : UInt32($0) ?? 0 }
                guard let first = ends.first else { continue }
                let last = ends.count > 1 ? ends[1] : first
                let range = min(first, last)...max(first, last)
                for message in messages where range.contains(message.uid) { wanted.insert(message.uid) }
            }
            return messages.map(\.uid).filter { wanted.contains($0) }
        }

        /// An IMAP atom or quoted string as plain text.
        static func unquoted(_ text: String) -> String {
            guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
    }
}
