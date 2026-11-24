// One SMTP conversation with the controlled mail server (plan §10.8): enough of RFC 5321 for a submission, with the
// message's `Message-ID` as the logical action's key. Messages are bounded; nothing is relayed anywhere.

import Foundation
import NIOCore

struct ControlledSMTPSession {
    static let maximumMessageBytes = 1_048_576
    let registry: ControlledRegistry

    func serve(_ connection: NIOAsyncChannel<ByteBuffer, ByteBuffer>) async {
        do {
            try await connection.executeThenClose { inbound, outbound in
                func reply(_ text: String) async throws { try await outbound.write(ByteBuffer(string: text + "\r\n")) }
                try await reply("220 controlled.invalid ESMTP controlled server, test only")
                var pending = ""
                var inData = false
                var message: [String] = []
                var size = 0
                for try await buffer in inbound {
                    pending += String(buffer: buffer)
                    while let end = pending.range(of: "\r\n") {
                        let line = String(pending[..<end.lowerBound])
                        pending.removeSubrange(..<end.upperBound)
                        if inData {
                            guard line != "." else {
                                inData = false
                                registry.classify(.send)
                                let key = Self.messageID(in: message) ?? ""
                                message = []
                                switch registry.admit(key: key, referencePrefix: "smtp-") {
                                case .answer: try await reply("250 2.0.0 accepted \(key)")
                                case .drop: return
                                case .rateLimited: try await reply("451 4.7.0 rate limited, try later")
                                }
                                continue
                            }
                            size += line.utf8.count + 2
                            guard size <= Self.maximumMessageBytes else {
                                try await reply("552 5.3.4 message too large")
                                return
                            }
                            message.append(line.hasPrefix("..") ? String(line.dropFirst()) : line)
                            continue
                        }
                        switch line.prefix(4).uppercased() {
                        case "EHLO", "HELO": try await reply("250 controlled.invalid")
                        case "MAIL", "RCPT", "RSET", "NOOP": try await reply("250 2.0.0 OK")
                        case "DATA":
                            inData = true
                            size = 0
                            try await reply("354 end with <CRLF>.<CRLF>")
                        case "QUIT":
                            try await reply("221 2.0.0 bye")
                            return
                        default: try await reply("502 5.5.1 not implemented")
                        }
                    }
                }
            }
        } catch {
            // The client went away; nothing to record.
        }
    }

    /// The `Message-ID` header's value from the message's header section.
    static func messageID(in lines: [String]) -> String? {
        for line in lines {
            if line.isEmpty { return nil }
            let lower = line.lowercased()
            if lower.hasPrefix("message-id:") {
                return line.dropFirst("message-id:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
