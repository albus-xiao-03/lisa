// Test-only. Builds synthetic RFC 5322 / MIME messages with CRLF line endings and example.com / example.invalid
// addresses, for the mail suites (L04, L19, L22) and later mail-ingestion tests (L05).

import Foundation

/// A synthetic message: header lines and a body, rendered with CRLF line endings.
struct SyntheticMail {
    /// Header lines in order, such as `("Subject", "Hello")`.
    var headers: [(name: String, value: String)]
    /// The body, written with `"\n"` line endings only.
    var body: String

    /// The message bytes, with every line ending as CRLF.
    var data: Data {
        let head = headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
        return Data((head + "\n\n" + body).replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    /// A typical message: From, To, an optional Cc, Subject, Date, Message-ID and MIME headers, then `body`.
    static func message(
        subject: String, from: String = "Sender <sender@example.com>", to: String = "Lisa <lisa@example.com>",
        cc: String? = nil, date: String = "Mon, 16 Nov 2026 09:30:00 -0500",
        messageID: String? = "<synthetic-1@example.com>", contentType: String? = "text/plain; charset=utf-8",
        extraHeaders: [(name: String, value: String)] = [], body: String
    ) -> SyntheticMail {
        var headers: [(name: String, value: String)] = [("From", from), ("To", to)]
        if let cc { headers.append(("Cc", cc)) }
        headers.append(("Subject", subject))
        headers.append(("Date", date))
        if let messageID { headers.append(("Message-ID", messageID)) }
        headers.append(("MIME-Version", "1.0"))
        if let contentType { headers.append(("Content-Type", contentType)) }
        return SyntheticMail(headers: headers + extraHeaders, body: body)
    }

    /// One MIME part: its header lines, a blank line and its body.
    static func part(_ headers: [(name: String, value: String)], body: String) -> String {
        headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n") + "\n\n" + body
    }

    /// A multipart body joining `parts` with `boundary`. The closing delimiter is left out when `closed` is false.
    static func multipart(boundary: String, parts: [String], closed: Bool = true) -> String {
        let opened = parts.map { "--\(boundary)\n\($0)\n" }.joined()
        return "This is a synthetic multipart message.\n" + opened + (closed ? "--\(boundary)--\n" : "")
    }

    /// `data` in base64 with 76-character lines, as a mail client writes an encoded part.
    static func base64Lines(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
    }
}
