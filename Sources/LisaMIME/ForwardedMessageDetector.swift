// Detects inline-forwarded originals (Gmail, Apple Mail, Outlook, Thunderbird markers) and their header lines.

import Foundation
import LisaTime

/// An inline-forwarded original found inside a message body.
public struct InlineForward: Hashable, Sendable {
    /// The forwarder's own note above the marker.
    public var note: String
    public var from: MailAddress?
    public var subject: String?
    public var sentAt: Date?
    public var body: String
}

/// Finds the first inline-forward marker in plain text.
public enum ForwardedMessageDetector {
    private static let markers = [
        "---------- forwarded message ---------", "begin forwarded message:", "-----original message-----",
        "-------- original message --------", "-------- forwarded message --------", "forwarded message:",
    ]

    public static func detect(in text: String) -> InlineForward? {
        let lines = text.components(separatedBy: "\n")
        guard
            let markerIndex = lines.firstIndex(where: { line in
                let normalized = line.trimmingCharacters(in: .whitespaces).lowercased()
                return markers.contains { normalized.hasPrefix($0) }
            })
        else { return nil }
        var from: MailAddress?
        var subject: String?
        var sentAt: Date?
        var index = markerIndex + 1
        while index < lines.count {
            var line = Substring(lines[index].trimmingCharacters(in: .whitespaces))
            while line.first == ">" || line.first == " " { line = line.dropFirst() }
            if line.isEmpty, index > markerIndex + 1 { break }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "from": from = MailAddress.parseList(value).first
                case "subject": subject = value
                // Zone-less forms such as Gmail's "Mon, Nov 16, 2026 at 9:30 AM" stay unparsed rather than guessed.
                case "date", "sent": sentAt = InternetDateParser.parse(value)
                default: break
                }
            }
            index += 1
        }
        let note = lines[..<markerIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines[min(index, lines.count)...].joined(separator: "\n").trimmingCharacters(
            in: .whitespacesAndNewlines)
        return InlineForward(note: note, from: from, subject: subject, sentAt: sentAt, body: body)
    }
}
