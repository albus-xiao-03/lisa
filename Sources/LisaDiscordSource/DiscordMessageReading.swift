// Reads one Discord message: renders the text a person would see, or says why the message cannot be read.

import Foundation

/// How Lisa reads a message.
enum DiscordMessageReading {
    enum Outcome: Hashable, Sendable {
        /// The message's visible text and its author's name.
        case readable(text: String, author: String?)
        /// A message type that carries content, with every content member empty: Discord withholds content from bots
        /// without the `MESSAGE_CONTENT` privileged intent ("An app will receive empty values in the `content`,
        /// `embeds`, `attachments`, and `components` fields while `poll` will be omitted",
        /// https://docs.discord.com/developers/resources/message.md#message-object).
        case contentWithheld
        /// Content Lisa cannot render, such as message components alone.
        case unsupportedContent
        /// A system message (member joined, message pinned, boost, ...), which is not news.
        case systemMessage
    }

    /// DEFAULT (0), REPLY (19), CHAT_INPUT_COMMAND (20) and CONTEXT_MENU_COMMAND (23): the types that carry what a person
    /// or app wrote. Every other type is a system notice.
    static let contentTypes: Set<Int> = [0, 19, 20, 23]
    /// The most bytes of one message's rendered text.
    static let maxTextBytes = 16_384
    /// The most bytes of an author's name.
    static let maxAuthorBytes = 64

    static func read(_ message: DiscordMessage) -> Outcome {
        guard contentTypes.contains(message.type) else { return .systemMessage }
        var parts = Self.lines(for: message.body)
        for snapshot in message.snapshots {
            let forwarded = Self.lines(for: snapshot)
            guard !forwarded.isEmpty else { continue }
            parts.append("Forwarded message:")
            parts += forwarded
        }
        let text = DiscordText.normalized(parts.joined(separator: "\n"), maxBytes: maxTextBytes)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let author = message.author?.displayName.map { DiscordText.singleLine($0, maxBytes: maxAuthorBytes) }
            return .readable(text: text, author: author?.isEmpty == false ? author : nil)
        }
        if message.body.isEmpty, message.snapshots.allSatisfy(\.isEmpty) { return .contentWithheld }
        return .unsupportedContent
    }

    /// The visible text of a message body: its content, embeds (title, description, link and fields), poll, and the
    /// names of its attachments and stickers. Attachments are listed, never opened.
    static func lines(for body: DiscordMessageBody) -> [String] {
        var lines: [String] = []
        if !body.content.isEmpty { lines.append(body.content) }
        for embed in body.embeds {
            for part in [embed.title, embed.description] {
                if let part, !part.isEmpty { lines.append(part) }
            }
            if let url = embed.url, url.hasPrefix("https://") || url.hasPrefix("http://") { lines.append(url) }
            for field in embed.fields {
                let name = field.name ?? ""
                let value = field.value ?? ""
                if !name.isEmpty || !value.isEmpty { lines.append(name.isEmpty ? value : "\(name): \(value)") }
            }
        }
        if let question = body.pollQuestion, !question.isEmpty {
            lines.append("Poll: \(question)")
            lines += body.pollAnswers.filter { !$0.isEmpty }.map { "- \($0)" }
        }
        for attachment in body.attachments {
            guard let name = attachment.filename, !name.isEmpty else { continue }
            let type = attachment.contentType.map { " (\($0))" } ?? ""
            lines.append("Attachment: \(name)\(type)")
        }
        lines += body.stickerNames.filter { !$0.isEmpty }.map { "Sticker: \($0)" }
        return lines
    }
}
