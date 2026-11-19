// Turns an EmailEnvelope into what one SMTP submission sends: checked envelope addresses, the EHLO name, and the
// RFC 5322 message that LisaMIME composes (UTF-8 quoted-printable text, CRLF line endings, not dot-stuffed).

import Foundation
import LisaMIME
import LisaPorts

/// One message, ready for libcurl.
struct SMTPSubmission: Hashable, Sendable {
    /// The sender address's domain, lowercased. It is never this machine's host name.
    let heloName: String
    let envelopeFrom: String
    /// Exactly the envelope's recipients, in order.
    let recipients: [String]
    /// The complete message with CRLF line endings. libcurl dot-stuffs it and adds the end-of-data line.
    let data: Data
    /// The Message-ID header value, with angle brackets.
    let messageID: String
}

/// Why an envelope could not become a message. Descriptions never contain addresses or content.
enum SMTPCompositionError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidSender
    case noRecipients
    case tooManyRecipients(limit: Int)
    case invalidRecipient(position: Int)
    case recipientLineTooLong
    case invalidMessageID
    case refusedByComposer
    case tooLarge(limit: Int)

    var description: String {
        switch self {
        case .invalidSender: "the sender is not an ASCII address of the form local@host"
        case .noRecipients: "the message has no recipients"
        case .tooManyRecipients(let limit): "the message has more than \(limit) recipients"
        case .invalidRecipient(let position): "recipient \(position) is not an ASCII address of the form local@host"
        case .recipientLineTooLong: "the recipient addresses do not fit on one 998-character To line"
        case .invalidMessageID: "the message identifier is not of the form <id@domain>"
        case .refusedByComposer: "LisaMIME refused the message headers"
        case .tooLarge(let limit): "the composed message is larger than \(limit) bytes"
        }
    }
}

/// Composes envelopes. Recipients arrive already checked against the owner's approved addresses by the outbox; this
/// step only checks their syntax and never adds, drops or rewrites one.
enum SMTPMessageComposition {
    static let maxRecipients = 10

    static func compose(_ envelope: EmailEnvelope, date: Date, maxMessageBytes: Int)
        -> Result<SMTPSubmission, SMTPCompositionError>
    {
        guard let sender = SMTPMailbox(envelope.from) else { return .failure(.invalidSender) }
        guard !envelope.to.isEmpty else { return .failure(.noRecipients) }
        guard envelope.to.count <= maxRecipients else { return .failure(.tooManyRecipients(limit: maxRecipients)) }
        var recipients: [SMTPMailbox] = []
        for (index, address) in envelope.to.enumerated() {
            guard let mailbox = SMTPMailbox(address) else { return .failure(.invalidRecipient(position: index + 1)) }
            recipients.append(mailbox)
        }
        // LisaMIME writes all recipients on one unfolded `To:` line.
        let addressBytes = recipients.reduce(0) { $0 + $1.address.utf8.count }
        let toLine = "To: ".utf8.count + addressBytes + ", ".utf8.count * (recipients.count - 1)
        guard toLine <= SMTPHeaderText.maxLineLength else { return .failure(.recipientLineTooLong) }
        guard let messageID = normalizedMessageID(envelope.messageID) else { return .failure(.invalidMessageID) }
        // Quoted-printable never shrinks text, so an oversized body is refused before it is encoded.
        guard envelope.textBody.utf8.count <= maxMessageBytes else {
            return .failure(.tooLarge(limit: maxMessageBytes))
        }
        let message = OutgoingMessage(
            from: MailAddress(
                displayName: SMTPHeaderText.displayName(envelope.fromName, address: sender.address),
                address: sender.address),
            to: recipients.map { MailAddress(displayName: nil, address: $0.address) },
            subject: SMTPHeaderText.subject(envelope.subject), textBody: envelope.textBody, messageID: messageID,
            date: date)
        let data: Data
        do {
            data = try MessageComposer.compose(message)
        } catch {
            // LisaMIME's errors can name an address, so only a fixed description is kept.
            return .failure(.refusedByComposer)
        }
        guard data.count <= maxMessageBytes else { return .failure(.tooLarge(limit: maxMessageBytes)) }
        return .success(
            SMTPSubmission(
                heloName: sender.domain, envelopeFrom: sender.address, recipients: recipients.map(\.address),
                data: data, messageID: "<\(messageID)>"))
    }

    /// The `id-left@id-right` of a message identifier given with or without angle brackets (RFC 5322 §3.6.4, with
    /// dot-atom-text on both sides), or `nil` when it is not one. LisaMIME adds the brackets.
    static func normalizedMessageID(_ value: String) -> String? {
        var text = Substring(value)
        if text.hasPrefix("<"), text.hasSuffix(">") { text = text.dropFirst().dropLast() }
        guard text.utf8.count <= 250 else { return nil }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, SMTPMailbox.isDotAtomText(parts[0]), SMTPMailbox.isDotAtomText(parts[1]) else {
            return nil
        }
        return String(text)
    }
}
