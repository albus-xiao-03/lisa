// Reduces a MIME tree to the facts Lisa uses: identity, addresses, text, forwards, calendar parts, attachments.

import Foundation
import LisaTime

/// A forwarded original carried as a `message/rfc822` part.
public struct AttachedForward: Hashable, Sendable {
    public var from: MailAddress?
    public var subject: String?
    public var sentAt: Date?
    public var text: String
}

/// The facts Lisa uses from one message.
public struct ParsedMail: Sendable {
    public var messageID: String?
    public var inReplyTo: String?
    public var references: [String]
    public var from: MailAddress?
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var subject: String
    public var sentAt: Date?
    /// The preferred plain text: text/plain when present, otherwise converted HTML.
    public var text: String
    /// Whether the text came from HTML conversion.
    public var textFromHTML: Bool
    public var attachedForwards: [AttachedForward]
    public var inlineForward: InlineForward?
    /// Raw text/calendar parts, handed to the calendar ingestion path.
    public var calendarParts: [Data]
    /// Attachments Lisa does not interpret (shown as unsupported; never executed or fetched).
    public var unsupportedAttachments: [String]
    public var warnings: [String]

    /// Builds the summary. `htmlToText` converts HTML to sanitized text; the caller supplies it so this module stays
    /// free of an HTML parser dependency.
    public static func from(
        _ entity: MIMEEntity, limits: MIMELimits = MIMELimits(), htmlToText: @escaping (String) -> String
    ) -> ParsedMail {
        var collector = Collector(htmlToText: htmlToText)
        collector.walk(entity, insideAlternative: false)
        var text = collector.plain.isEmpty ? collector.htmlConverted : collector.plain
        var warnings = collector.warnings
        if text.count > limits.maxTextCharacters {
            text = String(text.prefix(limits.maxTextCharacters))
            warnings.append("the message text was truncated at \(limits.maxTextCharacters) characters")
        }
        let headers = entity.headers
        return ParsedMail(
            messageID: headers.value("Message-ID").map(normalizeID),
            inReplyTo: headers.value("In-Reply-To").map(normalizeID),
            references: headers.value("References").map {
                $0.split(whereSeparator: \.isWhitespace).map { normalizeID(String($0)) }
            } ?? [],
            from: headers.value("From").flatMap { MailAddress.parseList($0).first },
            to: headers.values("To").flatMap(MailAddress.parseList),
            cc: headers.values("Cc").flatMap(MailAddress.parseList),
            subject: headers.value("Subject").map(EncodedWords.decode) ?? "",
            sentAt: headers.value("Date").flatMap(InternetDateParser.parseRFC5322),
            text: text, textFromHTML: collector.plain.isEmpty && !collector.htmlConverted.isEmpty,
            attachedForwards: collector.forwards, inlineForward: ForwardedMessageDetector.detect(in: text),
            calendarParts: collector.calendars, unsupportedAttachments: collector.unsupported, warnings: warnings)
    }

    static func normalizeID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }

    private struct Collector {
        let htmlToText: (String) -> String
        var plain = ""
        var htmlConverted = ""
        var forwards: [AttachedForward] = []
        var calendars: [Data] = []
        var unsupported: [String] = []
        var warnings: [String] = []

        mutating func walk(_ entity: MIMEEntity, insideAlternative: Bool) {
            warnings.append(contentsOf: entity.warnings)
            let type = entity.contentType
            if entity.isMultipart {
                let alternative = type.subtype == "alternative"
                if alternative,
                    let plainPart = entity.parts.first(where: {
                        $0.contentType.mimeType == "text/plain" && $0.disposition?.isAttachment != true
                    })
                {
                    append(plainText: plainPart)
                    for part in entity.parts where part.contentType.mimeType == "text/calendar" {
                        walk(part, insideAlternative: true)
                    }
                    return
                }
                for part in entity.parts { walk(part, insideAlternative: alternative) }
                return
            }
            if type.mimeType == "message/rfc822" {
                for embedded in entity.embedded {
                    var inner = Collector(htmlToText: htmlToText)
                    inner.walk(embedded, insideAlternative: false)
                    forwards.append(
                        AttachedForward(
                            from: embedded.headers.value("From").flatMap { MailAddress.parseList($0).first },
                            subject: embedded.headers.value("Subject").map(EncodedWords.decode),
                            sentAt: embedded.headers.value("Date").flatMap(InternetDateParser.parseRFC5322),
                            text: inner.plain.isEmpty ? inner.htmlConverted : inner.plain))
                    calendars.append(contentsOf: inner.calendars)
                    unsupported.append(contentsOf: inner.unsupported)
                }
                return
            }
            if type.mimeType == "text/calendar" || type.mimeType == "application/ics" {
                calendars.append(entity.body)
                return
            }
            let isAttachment = entity.disposition?.isAttachment == true
            if type.mimeType == "text/plain", !isAttachment {
                append(plainText: entity)
            } else if type.mimeType == "text/html", !isAttachment {
                let decoded = CharsetDecoder.decode(entity.body, charset: type.charset)
                if !decoded.faithful { warnings.append("an HTML part used an unsupported charset") }
                let converted = htmlToText(decoded.text)
                htmlConverted += (htmlConverted.isEmpty ? "" : "\n\n") + converted
            } else {
                let name = entity.disposition?.filename ?? type.parameters["name"].map(EncodedWords.decode)
                unsupported.append("\(name ?? "unnamed") (\(type.mimeType))")
            }
        }

        mutating func append(plainText entity: MIMEEntity) {
            let decoded = CharsetDecoder.decode(entity.body, charset: entity.contentType.charset)
            if !decoded.faithful { warnings.append("a text part used an unsupported charset") }
            plain += (plain.isEmpty ? "" : "\n\n") + decoded.text.replacingOccurrences(of: "\r\n", with: "\n")
        }
    }
}
