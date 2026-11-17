// Turns new channel messages into fetched items in the news-ingestion contract, and reports what could not be read.

import Foundation
import LisaPorts
import LisaTime

/// Maps messages to `FetchedItem`s of kind `.post`, as news ingestion reads them: the item data is the message's
/// visible text as UTF-8, `metadata["title"]` is the author's name and the first line, `receivedAt` is when the message
/// was sent, and `externalID` (`discord:<channel>:<message>`) is the stable key. Discord documents no message link in
/// these pages, so no `metadata["url"]` is set.
enum DiscordMessageMapping {
    /// The capability notes and failure summaries. They contain no counts, so repeated synchronizations do not pile
    /// up variants of the same note.
    enum Note {
        static let contentWithheld =
            "Discord withheld the content of some messages because the bot lacks the Message Content privileged"
            + " intent (MESSAGE_CONTENT); those messages were skipped. Enable the intent for the bot in the Discord"
            + " Developer Portal, or share such messages with Lisa manually"
        static let monitoringUnavailable =
            "automatic monitoring of this channel is unavailable: Discord withholds message content from the bot"
            + " because it lacks the Message Content privileged intent (MESSAGE_CONTENT). Enable the intent for the bot"
            + " in the Discord Developer Portal, or share messages with Lisa manually"
        static let unsupportedContent =
            "some messages hold only content Lisa cannot read, such as message components; they were skipped"
        static let emptyFirstRead =
            "Discord returned no messages for this channel. If it has messages, the bot may lack the Read Message"
            + " History permission, in which case Discord returns none"
    }

    struct Result: Sendable {
        var items: [FetchedItem]
        var notes: [String]
        /// Messages that carry content Lisa could read.
        var readable: Int
        /// Messages whose content Discord withheld.
        var withheld: Int
    }

    /// The longest title kept; news ingestion shortens titles further.
    static let maxTitleBytes = 160

    static func map(_ messages: [(snowflake: UInt64, message: DiscordMessage)], channelID: String) -> Result {
        var result = Result(items: [], notes: [], readable: 0, withheld: 0)
        var unsupported = false
        for (snowflake, message) in messages {
            switch DiscordMessageReading.read(message) {
            case .readable(let text, let author):
                result.readable += 1
                let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
                let heading = author.map { "\($0): \(firstLine)" } ?? firstLine
                let title = DiscordText.singleLine(heading, maxBytes: maxTitleBytes)
                let sent =
                    message.timestamp.flatMap(InternetDateParser.parseISO8601) ?? DiscordSnowflake.date(of: snowflake)
                result.items.append(
                    FetchedItem(
                        externalID: "discord:\(channelID):\(message.id)", kind: .post, data: Data(text.utf8),
                        receivedAt: sent, metadata: ["title": title]))
            case .contentWithheld:
                result.withheld += 1
            case .unsupportedContent:
                unsupported = true
            case .systemMessage:
                continue
            }
        }
        if result.withheld > 0 { result.notes.append(Note.contentWithheld) }
        if unsupported { result.notes.append(Note.unsupportedContent) }
        return result
    }
}
