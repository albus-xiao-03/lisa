// The configuration of one Discord channel source: the channel ID, the bot-token reference and the User-Agent.

import LisaPorts
import LisaSecrets

/// One explicitly configured channel, read by the owner's authorized bot (NEWS-03). The token is a bot token, never
/// the owner's own account token; it is only referenced here and resolved from the secret store at each fetch.
public struct DiscordChannelConfiguration: Hashable, Sendable {
    /// The channel's snowflake ID.
    public var channelID: String
    /// Where the bot token is kept, such as `env:LISA_DISCORD_BOT_TOKEN`. It is sent as `Authorization: Bot <token>`.
    public var botToken: SecretReference
    /// The `User-Agent` sent with every request.
    public var userAgent: DiscordUserAgent

    public init(channelID: String, botToken: SecretReference, userAgent: DiscordUserAgent) {
        self.channelID = channelID
        self.botToken = botToken
        self.userAgent = userAgent
    }

    /// Checks the configuration without contacting Discord.
    func validate() throws(ConnectorError) {
        guard let value = DiscordSnowflake.value(channelID), value > 0 else {
            throw ConnectorError(.configuration, "the Discord channel ID must be a snowflake of 1 to 20 digits")
        }
        try userAgent.validate()
    }
}
