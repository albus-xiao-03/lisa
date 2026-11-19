// Decodes and checks one page of channel messages: a bounded JSON array of messages with valid snowflake IDs.

import Foundation
import LisaPorts

/// A decoded page: its messages, each with its numeric ID, oldest first.
struct DiscordMessagePage: Sendable {
    var messages: [(snowflake: UInt64, message: DiscordMessage)]

    var snowflakes: [UInt64] { messages.map(\.snowflake) }

    /// Decodes Get Channel Messages' array. Discord documents the order as "newest to oldest", but nothing relies on
    /// it: messages are sorted by ID, and a repeated ID is kept once.
    static func decode(_ body: Data, pageSize: Int) throws(ConnectorError) -> DiscordMessagePage {
        let decoded: [DiscordMessage]
        do {
            decoded = try JSONDecoder().decode([DiscordMessage].self, from: body)
        } catch {
            throw ConnectorError(.parse, "the Discord response was not the expected JSON")
        }
        guard decoded.count <= pageSize else {
            throw ConnectorError(.parse, "Discord returned more messages than were requested")
        }
        var seen: Set<UInt64> = []
        var messages: [(snowflake: UInt64, message: DiscordMessage)] = []
        for message in decoded {
            guard let snowflake = DiscordSnowflake.value(message.id) else {
                throw ConnectorError(.parse, "Discord returned a message without a valid ID")
            }
            if seen.insert(snowflake).inserted { messages.append((snowflake, message)) }
        }
        messages.sort { $0.snowflake < $1.snowflake }
        return DiscordMessagePage(messages: messages)
    }
}
