// The members of Discord message objects that Lisa reads, decoded defensively: identity, author and content fields.

import Foundation

/// The member names of a message object (https://docs.discord.com/developers/resources/message.md#message-object), also
/// used for the partial messages inside forwarded-message snapshots.
enum DiscordMessageKey: String, CodingKey {
    case id
    case type
    case timestamp
    case author
    case content
    case embeds
    case attachments
    case components
    case poll
    case stickerItems = "sticker_items"
    case messageSnapshots = "message_snapshots"
    case message
}

/// One message from Get Channel Messages.
struct DiscordMessage: Hashable, Sendable {
    var id: String
    /// The message type; 0 is DEFAULT and 19 is REPLY.
    var type: Int
    /// "when this message was sent", ISO 8601.
    var timestamp: String?
    var author: DiscordAuthor?
    var body: DiscordMessageBody
    /// The forwarded messages' content (`message_snapshots[].message`).
    var snapshots: [DiscordMessageBody]
}

extension DiscordMessage: Decodable {
    /// `id` and `type` are required; every content member is optional and ignored when it has an unexpected shape.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DiscordMessageKey.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(Int.self, forKey: .type)
        timestamp = container.lenient(String.self, forKey: .timestamp)
        author = container.lenient(DiscordAuthor.self, forKey: .author)
        body = DiscordMessageBody(container)
        snapshots = container.lenientArray(DiscordSnapshot.self, forKey: .messageSnapshots, limit: 5).map(\.body)
    }
}

/// The content-bearing members of a message. Without the `MESSAGE_CONTENT` privileged intent, Discord sends `content`,
/// `embeds`, `attachments` and `components` empty and omits `poll`
/// (https://docs.discord.com/developers/events/gateway.md#message-content-intent).
struct DiscordMessageBody: Hashable, Sendable {
    /// The most embeds, attachments and stickers read from one message (Discord allows 10 embeds per message).
    static let maxParts = 10

    var content: String
    var embeds: [DiscordEmbed]
    var attachments: [DiscordAttachment]
    var stickerNames: [String]
    var componentCount: Int
    var hasPoll: Bool
    var pollQuestion: String?
    var pollAnswers: [String]

    init(
        content: String = "", embeds: [DiscordEmbed] = [], attachments: [DiscordAttachment] = [],
        stickerNames: [String] = [], componentCount: Int = 0, hasPoll: Bool = false, pollQuestion: String? = nil,
        pollAnswers: [String] = []
    ) {
        self.content = content
        self.embeds = embeds
        self.attachments = attachments
        self.stickerNames = stickerNames
        self.componentCount = componentCount
        self.hasPoll = hasPoll
        self.pollQuestion = pollQuestion
        self.pollAnswers = pollAnswers
    }

    init(_ container: KeyedDecodingContainer<DiscordMessageKey>) {
        content = container.lenient(String.self, forKey: .content) ?? ""
        embeds = container.lenientArray(DiscordEmbed.self, forKey: .embeds, limit: Self.maxParts)
        attachments = container.lenientArray(DiscordAttachment.self, forKey: .attachments, limit: Self.maxParts)
        stickerNames = container.lenientArray(DiscordSticker.self, forKey: .stickerItems, limit: Self.maxParts)
            .compactMap(\.name)
        componentCount = container.arrayCount(forKey: .components)
        hasPoll = container.isPresent(.poll)
        let poll = container.lenient(DiscordPoll.self, forKey: .poll)
        pollQuestion = poll?.question
        pollAnswers = poll?.answers ?? []
    }

    /// Whether every content-bearing member is empty or absent.
    var isEmpty: Bool {
        content.isEmpty && embeds.isEmpty && attachments.isEmpty && stickerNames.isEmpty && componentCount == 0
            && !hasPoll
    }
}

/// A forwarded message (`message_snapshots[]`): "a minimal subset of fields" of the original, without its author.
struct DiscordSnapshot: Decodable {
    var body: DiscordMessageBody

    init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: DiscordMessageKey.self)
        body = DiscordMessageBody(try outer.nestedContainer(keyedBy: DiscordMessageKey.self, forKey: .message))
    }
}

/// The message author: a user, or for webhook messages the webhook's name.
struct DiscordAuthor: Hashable, Sendable, Decodable {
    var username: String?
    var globalName: String?

    private enum CodingKeys: String, CodingKey {
        case username
        case globalName = "global_name"
    }

    init(username: String? = nil, globalName: String? = nil) {
        self.username = username
        self.globalName = globalName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = container.lenient(String.self, forKey: .username)
        globalName = container.lenient(String.self, forKey: .globalName)
    }

    /// The name to show: the display name when set, otherwise the username.
    var displayName: String? {
        if let globalName, !globalName.isEmpty { return globalName }
        if let username, !username.isEmpty { return username }
        return nil
    }
}

/// An embed's text members.
struct DiscordEmbed: Hashable, Sendable, Decodable {
    var title: String?
    var description: String?
    var url: String?
    var fields: [DiscordEmbedField]

    private enum CodingKeys: String, CodingKey {
        case title
        case description
        case url
        case fields
    }

    init(title: String? = nil, description: String? = nil, url: String? = nil, fields: [DiscordEmbedField] = []) {
        self.title = title
        self.description = description
        self.url = url
        self.fields = fields
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.lenient(String.self, forKey: .title)
        description = container.lenient(String.self, forKey: .description)
        url = container.lenient(String.self, forKey: .url)
        fields = container.lenientArray(DiscordEmbedField.self, forKey: .fields, limit: 25)
    }
}

/// An embed field: a name and a value.
struct DiscordEmbedField: Hashable, Sendable, Decodable {
    var name: String?
    var value: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    init(name: String? = nil, value: String? = nil) {
        self.name = name
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name)
        value = container.lenient(String.self, forKey: .value)
    }
}

/// An attachment's name and media type. Its URLs are signed and expire, so they are not kept.
struct DiscordAttachment: Hashable, Sendable, Decodable {
    var filename: String?
    var contentType: String?

    private enum CodingKeys: String, CodingKey {
        case filename
        case contentType = "content_type"
    }

    init(filename: String? = nil, contentType: String? = nil) {
        self.filename = filename
        self.contentType = contentType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = container.lenient(String.self, forKey: .filename)
        contentType = container.lenient(String.self, forKey: .contentType)
    }
}

/// A sticker item's name.
private struct DiscordSticker: Decodable {
    var name: String?

    private enum CodingKeys: String, CodingKey {
        case name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.lenient(String.self, forKey: .name)
    }
}

/// A poll's question and answer texts (`question.text`, `answers[].poll_media.text`).
private struct DiscordPoll: Decodable {
    var question: String?
    var answers: [String]

    private struct Media: Decodable {
        var text: String?

        private enum CodingKeys: String, CodingKey {
            case text
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = container.lenient(String.self, forKey: .text)
        }
    }

    private struct Answer: Decodable {
        var media: Media?

        private enum CodingKeys: String, CodingKey {
            case media = "poll_media"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            media = container.lenient(Media.self, forKey: .media)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case question
        case answers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = container.lenient(Media.self, forKey: .question)?.text
        answers = container.lenientArray(Answer.self, forKey: .answers, limit: 10).compactMap { $0.media?.text }
    }
}
