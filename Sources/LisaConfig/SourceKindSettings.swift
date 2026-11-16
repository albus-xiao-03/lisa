// Kind-specific source settings: Lisa's IMAP mailbox, calendar and news feeds, X accounts, Discord channels, imports.

import Foundation
import LisaDomain
import LisaSecrets
import LisaTime

/// Lisa's own dedicated mailbox, read over IMAP with TLS (MAIL-01). Retrieval is read-only, and the owner's personal
/// mailbox is never configured here.
public struct MailboxSourceSettings: Hashable, Sendable {
    /// The IMAP server, such as `imap.example.com`.
    public let host: String
    /// Defaults to 993 for implicit TLS and 143 for STARTTLS.
    public let port: Int
    /// TLS from the first byte, or a required STARTTLS upgrade.
    public let security: TransportSecurity
    /// The account name of Lisa's mailbox.
    public let username: String
    /// The reference to the mailbox password.
    public let passwordSecret: SecretReference
    /// The folder read; defaults to `INBOX`.
    public let folder: String
    /// Lisa's own address, which the owner forwards or copies messages to. Never one of the owner's addresses.
    public let mailboxAddress: String

    static func decode(_ section: ConfigSection) -> MailboxSourceSettings? {
        let host = section.requiredValidated(
            "host", maxLength: 253, fix: "name the IMAP server of Lisa's mailbox, such as imap.example.com",
            NetworkAddressRules.serverHost)
        let security = section.choice("security", default: .implicitTLS, options: TransportSecurity.allCases)
        let port = section.integer("port", default: security == .implicitTLS ? 993 : 143, in: 1...65_535)
        let username = section.requiredText("username", maxLength: 320, fix: "the account name of Lisa's mailbox")
        let passwordSecret = section.requiredSecret(
            "passwordSecret", fix: "reference the mailbox password, such as env:LISA_IMAP_PASSWORD")
        let folder = section.text("folder", maxLength: 255) ?? "INBOX"
        let mailboxAddress = section.requiredValidated(
            "mailboxAddress", maxLength: 254, fix: "Lisa's own address, which the owner forwards messages to",
            DeliveryConfiguration.emailAddress)
        guard let host, let username, let passwordSecret, let mailboxAddress else { return nil }
        return MailboxSourceSettings(
            host: host, port: port, security: security, username: username, passwordSecret: passwordSecret,
            folder: folder, mailboxAddress: mailboxAddress)
    }
}

/// Where a feed is read from.
public enum FeedLocation: Hashable, Sendable {
    /// A public https address.
    case url(URL)
    /// An address kept as a secret, such as a calendar's private subscription address (CAL-01). It must resolve to an
    /// https address; that is checked when the source is read.
    case secretURL(SecretReference)
    /// A local file (calendar feeds only).
    case file(String)

    /// Exactly one of `url`, `urlSecret` and, when allowed, `file`.
    static func decode(_ section: ConfigSection, allowsFile: Bool) -> FeedLocation? {
        let url = section.validated("url", maxLength: 2048, NetworkAddressRules.httpsURL)
        let urlSecret = section.secret("urlSecret")
        let file: String? =
            allowsFile
            ? section.validated("file", maxLength: 1024) {
                FilePathRules.absolutePath($0, homeDirectory: section.context.homeDirectory)
            } : nil
        let keys = ["url", "urlSecret"] + (allowsFile ? ["file"] : [])
        let setKeys = keys.filter { section.isSet($0) }
        let choices = allowsFile ? "url, urlSecret or file" : "url or urlSecret"
        guard setKeys.count == 1 else {
            if setKeys.isEmpty {
                section.reportMissing("url", fix: "set exactly one of \(choices)")
            } else {
                section.report(setKeys[1], "conflicts with \(setKeys[0])", fix: "set exactly one of \(choices)")
            }
            return nil
        }
        if let url { return .url(url) }
        if let urlSecret { return .secretURL(urlSecret) }
        if let file { return .file(file) }
        return nil
    }
}

/// An iCalendar subscription or local `.ics` file (CAL-01), read only.
public struct CalendarFeedSourceSettings: Hashable, Sendable {
    /// A public https address, a secret private address, or a local `.ics` file.
    public let location: FeedLocation
    /// The zone that floating times (times without a zone) are read in; defaults to the configured `timeZone`.
    public let floatingTimeZone: TimeZoneID

    static func decode(_ section: ConfigSection, defaultZone: TimeZoneID) -> CalendarFeedSourceSettings? {
        let location = FeedLocation.decode(section, allowsFile: true)
        let zone = section.timeZone("floatingTimeZone") ?? defaultZone
        return location.map { CalendarFeedSourceSettings(location: $0, floatingTimeZone: zone) }
    }
}

/// An RSS or Atom feed (NEWS-01).
public struct NewsFeedSourceSettings: Hashable, Sendable {
    /// A public https address, or a private address kept as a secret.
    public let location: FeedLocation

    static func decode(_ section: ConfigSection) -> NewsFeedSourceSettings? {
        FeedLocation.decode(section, allowsFile: false).map(NewsFeedSourceSettings.init)
    }
}

/// A selected X account read through the official API (NEWS-02).
public struct XAccountSourceSettings: Hashable, Sendable {
    /// The account's numeric user ID.
    public let userID: String
    /// The reference to the X API bearer token.
    public let bearerTokenSecret: SecretReference

    static func decode(_ section: ConfigSection) -> XAccountSourceSettings? {
        let userID = section.requiredValidated(
            "userID", maxLength: 20, fix: "the account's numeric X user ID", numericIdentifier)
        let bearerTokenSecret = section.requiredSecret(
            "bearerTokenSecret", fix: "reference the X API bearer token, such as env:LISA_X_BEARER_TOKEN")
        guard let userID, let bearerTokenSecret else { return nil }
        return XAccountSourceSettings(userID: userID, bearerTokenSecret: bearerTokenSecret)
    }
}

/// A Discord channel read by an authorized bot (NEWS-03). The token is a bot token, never the owner's own.
public struct DiscordChannelSourceSettings: Hashable, Sendable {
    /// The channel's numeric ID.
    public let channelID: String
    /// The reference to the bot token.
    public let botTokenSecret: SecretReference

    static func decode(_ section: ConfigSection) -> DiscordChannelSourceSettings? {
        let channelID = section.requiredValidated(
            "channelID", maxLength: 20, fix: "the channel's numeric ID", numericIdentifier)
        let botTokenSecret = section.requiredSecret(
            "botTokenSecret", fix: "reference the bot token, such as env:LISA_DISCORD_BOT_TOKEN")
        guard let channelID, let botTokenSecret else { return nil }
        return DiscordChannelSourceSettings(channelID: channelID, botTokenSecret: botTokenSecret)
    }
}

/// The kind of files a local import directory holds.
public enum LocalImportFormat: String, Hashable, Sendable, CaseIterable {
    /// `.eml` messages, read like Lisa's mailbox.
    case mail
    /// `.ics` calendars.
    case calendar
}

/// A local directory of exported files.
public struct LocalImportSourceSettings: Hashable, Sendable {
    /// An absolute path; a leading `~` is expanded.
    public let directory: String
    /// Whether the directory holds messages or calendars.
    public let format: LocalImportFormat

    static func decode(_ section: ConfigSection) -> LocalImportSourceSettings? {
        let directory = section.requiredValidated(
            "directory", maxLength: 1024, fix: "an absolute path, or one starting with ~/"
        ) { FilePathRules.absolutePath($0, homeDirectory: section.context.homeDirectory) }
        let format = section.requiredChoice("format", options: LocalImportFormat.allCases)
        guard let directory, let format else { return nil }
        return LocalImportSourceSettings(directory: directory, format: format)
    }
}

/// A source's kind and its kind-specific settings.
public enum SourceKindSettings: Hashable, Sendable {
    /// Lisa's own IMAP mailbox.
    case mailbox(MailboxSourceSettings)
    /// An iCalendar subscription or file.
    case calendarFeed(CalendarFeedSourceSettings)
    /// An RSS or Atom feed.
    case newsFeed(NewsFeedSourceSettings)
    /// An X account.
    case xAccount(XAccountSourceSettings)
    /// A Discord channel.
    case discordChannel(DiscordChannelSourceSettings)
    /// A local import directory.
    case localImport(LocalImportSourceSettings)

    /// The domain kind recorded on the `Source`.
    public var kind: SourceKind {
        switch self {
        case .mailbox: .mailbox
        case .calendarFeed: .calendarFeed
        case .newsFeed: .newsFeed
        case .xAccount: .xAccount
        case .discordChannel: .discordChannel
        case .localImport: .localImport
        }
    }

    static func decode(_ kind: SourceKind, section: ConfigSection, defaultZone: TimeZoneID) -> SourceKindSettings? {
        switch kind {
        case .mailbox: MailboxSourceSettings.decode(section).map(Self.mailbox)
        case .calendarFeed: CalendarFeedSourceSettings.decode(section, defaultZone: defaultZone).map(Self.calendarFeed)
        case .newsFeed: NewsFeedSourceSettings.decode(section).map(Self.newsFeed)
        case .xAccount: XAccountSourceSettings.decode(section).map(Self.xAccount)
        case .discordChannel: DiscordChannelSourceSettings.decode(section).map(Self.discordChannel)
        case .localImport: LocalImportSourceSettings.decode(section).map(Self.localImport)
        case .manualCapture: nil
        }
    }
}

/// X user IDs and Discord channel IDs: 1 to 20 ASCII digits.
private func numericIdentifier(_ text: String) -> Result<String, ValueRefusal> {
    let valid = (1...20).contains(text.utf8.count) && text.utf8.allSatisfy { (0x30...0x39).contains($0) }
    return valid ? .success(text) : .failure(ValueRefusal("must be a numeric ID of 1 to 20 digits"))
}
