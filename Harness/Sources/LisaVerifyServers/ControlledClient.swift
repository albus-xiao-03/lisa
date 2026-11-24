// The harness's own client for fixture actions it performs itself against the controlled servers (plan §10.8 "The
// action ledger" step 2: a step the harness performs itself is marked `submitting` before the first byte). Loopback
// only; every exchange is bounded by a timeout.

import Foundation
import NIOCore
import NIOPosix

/// Submits fixture actions to, and looks them up on, the controlled servers.
public enum ControlledClient {
    /// What a submission's answer showed.
    public enum Outcome: Sendable, Equatable {
        case accepted(reference: String)
        case refused(status: Int)
        /// The connection closed without an answer: the server may have accepted it.
        case noAnswer
    }

    public enum Failure: Error, Sendable, Equatable {
        case timedOut
    }

    /// Sends one email whose `Message-ID` is the logical action's key.
    public static func sendEmail(port: Int, messageID: String, recipientAlias: String) async throws -> Outcome {
        try await withTimeout {
            let channel = try await connect(port)
            return try await channel.executeThenClose { inbound, outbound in
                var reader = ReplyReader(iterator: inbound.makeAsyncIterator())
                guard let greeting = try await reader.reply(), greeting.hasPrefix("220") else { return .noAnswer }
                let commands = [
                    ("EHLO lisa-verify.invalid", 250), ("MAIL FROM:<harness@lisa-verify.invalid>", 250),
                    ("RCPT TO:<\(recipientAlias)@lisa-verify.invalid>", 250), ("DATA", 354),
                ]
                for (command, expected) in commands {
                    try await outbound.write(ByteBuffer(string: command + "\r\n"))
                    guard let reply = try await reader.reply() else { return .noAnswer }
                    let code = Int(reply.prefix(3)) ?? 0
                    guard code == expected else { return .refused(status: code) }
                }
                let message =
                    "Message-ID: \(messageID)\r\nSubject: LISA-VERIFY fixture\r\nFrom: <harness@lisa-verify.invalid>\r\n"
                    + "To: <\(recipientAlias)@lisa-verify.invalid>\r\n\r\nFixture message; controlled server only.\r\n.\r\n"
                try await outbound.write(ByteBuffer(string: message))
                guard let reply = try await reader.reply() else { return .noAnswer }
                let code = Int(reply.prefix(3)) ?? 0
                guard code == 250 else { return .refused(status: code) }
                try? await outbound.write(ByteBuffer(string: "QUIT\r\n"))
                return .accepted(reference: messageID)
            }
        }
    }

    /// Posts a push, model request or call in its provider's shape, keyed by `operationID`.
    public static func post(port: Int, path: String, operationID: String, body: String) async throws -> Outcome {
        let request =
            "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\nContent-Type: application/json\r\n"
            + "Lisa-Operation-ID: \(operationID)\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard let response = try await exchange(port: port, request: request) else { return .noAnswer }
        guard (200..<300).contains(response.status) else { return .refused(status: response.status) }
        return .accepted(reference: response.headers["lisa-reference"] ?? "")
    }

    /// The controlled servers' lookup by the action's key.
    public static func lookup(port: Int, key: String) async throws -> ControlledRegistry.Lookup {
        var components = URLComponents()
        components.path = "/_controlled/lookup"
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        let target = components.percentEncodedPath + "?" + (components.percentEncodedQuery ?? "")
        let request = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
        guard let response = try await exchange(port: port, request: request) else { return .disabled }
        switch response.status {
        case 200:
            let object = (try? JSONSerialization.jsonObject(with: Data(response.body.utf8))) as? [String: Any]
            return .found(reference: object?["reference"] as? String ?? "", count: object?["count"] as? Int ?? 0)
        case 404: return .notFound
        default: return .disabled
        }
    }

    struct Response {
        let status: Int
        let headers: [String: String]
        let body: String
    }

    /// One HTTP/1.1 exchange read to the connection's close; nil when it closed without any byte.
    static func exchange(port: Int, request: String) async throws -> Response? {
        try await withTimeout {
            let channel = try await connect(port)
            return try await channel.executeThenClose { inbound, outbound in
                try await outbound.write(ByteBuffer(string: request))
                var bytes: [UInt8] = []
                for try await buffer in inbound { bytes += buffer.readableBytesView }
                guard !bytes.isEmpty else { return nil }
                let text = String(decoding: bytes, as: UTF8.self)
                let parts = text.components(separatedBy: "\r\n\r\n")
                let lines = parts[0].components(separatedBy: "\r\n")
                let status = Int(lines[0].split(separator: " ").dropFirst().first ?? "") ?? 0
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[line[..<colon].lowercased()] = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                }
                return Response(status: status, headers: headers, body: parts.dropFirst().joined(separator: "\r\n\r\n"))
            }
        }
    }

    static func connect(_ port: Int) async throws -> NIOAsyncChannel<ByteBuffer, ByteBuffer> {
        try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connect(host: "127.0.0.1", port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }
    }

    static func withTimeout<T: Sendable>(
        seconds: Double = 10, _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw Failure.timedOut
            }
            guard let result = try await group.next() else { throw Failure.timedOut }
            group.cancelAll()
            return result
        }
    }

    /// Reads SMTP replies, folding multi-line ones to their last line.
    struct ReplyReader {
        var iterator: NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
        var pending = ""

        mutating func reply() async throws -> String? {
            while true {
                if let end = pending.range(of: "\r\n") {
                    let line = String(pending[..<end.lowerBound])
                    pending.removeSubrange(..<end.upperBound)
                    if line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == "-" { continue }
                    return line
                }
                guard let buffer = try await iterator.next() else { return nil }
                pending += String(buffer: buffer)
            }
        }
    }
}
