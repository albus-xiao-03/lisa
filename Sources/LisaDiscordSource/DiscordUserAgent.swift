// The User-Agent Discord requires from HTTP API clients: DiscordBot ($url, $versionNumber).

import LisaPorts

/// Discord: "Clients using the HTTP API must provide a valid User Agent which specifies information about the client
/// library and version in the following format: `User-Agent: DiscordBot ($url, $versionNumber)`"; requests without one
/// "may be blocked" (https://docs.discord.com/developers/reference.md#user-agent).
public struct DiscordUserAgent: Hashable, Sendable {
    /// Lisa has no public homepage, so the default URL uses the reserved `.invalid` top-level domain: it names no
    /// person, account or deployment. An owner who runs the bot under a page of their own can set it instead.
    public static let defaultURL = "https://lisa.invalid"

    /// A URL about the client.
    public var url: String
    /// The client's version, such as Lisa's application version.
    public var version: String

    public init(url: String = DiscordUserAgent.defaultURL, version: String) {
        self.url = url
        self.version = version
    }

    /// The header value.
    public var headerValue: String { "DiscordBot (\(url), \(version))" }

    /// An https URL without spaces, commas or parentheses, and a version of letters, digits, `.`, `+` and `-`, so the
    /// header keeps Discord's format.
    func validate() throws(ConnectorError) {
        let urlValid =
            url.hasPrefix("https://") && (9...200).contains(url.utf8.count)
            && url.utf8.allSatisfy { byte in
                (0x21...0x7E).contains(byte) && byte != 0x2C && byte != 0x28 && byte != 0x29
            }
        let versionValid =
            (1...32).contains(version.utf8.count)
            && version.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                    || byte == 0x2E || byte == 0x2B || byte == 0x2D
            }
        guard urlValid, versionValid else {
            throw ConnectorError(
                .configuration,
                "the Discord User-Agent needs an https URL without spaces, commas or parentheses and a version of"
                    + " letters, digits, '.', '+' or '-'")
        }
    }
}
