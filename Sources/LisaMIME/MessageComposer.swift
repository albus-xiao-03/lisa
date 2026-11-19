// Composes outbound plain-text messages with RFC 5322 headers, refusing header injection.

import Foundation
import LisaTime

/// An outbound message. Recipients are validated by the delivery policy before composition.
public struct OutgoingMessage: Hashable, Sendable {
    public var from: MailAddress
    public var to: [MailAddress]
    public var subject: String
    public var textBody: String
    public var messageID: String
    public var date: Date

    public init(from: MailAddress, to: [MailAddress], subject: String, textBody: String, messageID: String, date: Date)
    {
        self.from = from
        self.to = to
        self.subject = subject
        self.textBody = textBody
        self.messageID = messageID
        self.date = date
    }
}

/// Serializes outbound messages.
public enum MessageComposer {
    /// The RFC 5322 wire form with CRLF line endings, UTF-8 quoted-printable body and `Auto-Submitted`.
    public static func compose(_ message: OutgoingMessage) throws -> Data {
        for address in [message.from] + message.to {
            guard MailAddress.isValid(address.address) else { throw MIMEError.invalidAddress(address.address) }
        }
        let headers: [(String, String)] = [
            ("From", format(message.from)),
            ("To", message.to.map(format).joined(separator: ", ")),
            ("Subject", EncodedWords.encodeIfNeeded(message.subject)),
            ("Date", rfc5322Date(message.date)),
            ("Message-ID", "<\(message.messageID)>"),
            ("MIME-Version", "1.0"),
            ("Content-Type", "text/plain; charset=UTF-8"),
            ("Content-Transfer-Encoding", "quoted-printable"),
            ("Auto-Submitted", "auto-generated"),
        ]
        var wire = ""
        for (name, value) in headers {
            guard !value.contains("\r"), !value.contains("\n") else { throw MIMEError.headerInjection(name) }
            wire += "\(name): \(value)\r\n"
        }
        wire += "\r\n" + TransferDecoding.encodeQuotedPrintable(message.textBody) + "\r\n"
        return Data(wire.utf8)
    }

    private static func format(_ address: MailAddress) -> String {
        guard let name = address.displayName, !name.isEmpty else { return address.address }
        let encoded = EncodedWords.encodeIfNeeded(name)
        let quoted = encoded == name ? "\"\(name.replacingOccurrences(of: "\"", with: ""))\"" : encoded
        return "\(quoted) <\(address.address)>"
    }

    /// Formats `date` as an RFC 5322 date in UTC, such as `Mon, 16 Nov 2026 14:30:00 +0000`.
    public static func rfc5322Date(_ date: Date) -> String {
        let local = ZoneRules.local(for: date, rules: FixedOffsetRules(seconds: 0))
        let weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][local.date.weekday.rawValue - 1]
        let month = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][
            local.date.month - 1]
        return String(
            format: "%@, %02d %@ %04d %02d:%02d:%02d +0000", weekday, local.date.day, month, local.date.year,
            local.time.hour, local.time.minute, local.time.second)
    }
}
