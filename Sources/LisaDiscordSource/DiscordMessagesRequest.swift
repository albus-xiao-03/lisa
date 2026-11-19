// Builds the request for one page of channel messages: GET /channels/{id}/messages on Discord's v10 REST API.

import Foundation
import LisaHTTP
import LisaPorts
import LisaRedaction

/// Discord's Get Channel Messages request (https://docs.discord.com/developers/resources/message.md#get-channel-messages).
enum DiscordMessagesRequest {
    /// The versioned base URL. Version 10 is "Available"; an unversioned route would follow Discord's default version,
    /// so the version is pinned (https://docs.discord.com/developers/reference.md#api-versioning).
    static let apiBase = "https://discord.com/api/v10"
    /// `limit` accepts 1 to 100.
    static let pageSizeRange = 1...100
    /// The largest page accepted, whatever the synchronization limit.
    static let maxPageBytes = 16 * 1_048_576
    /// Connection setup (DNS, TCP, TLS) gets at most this long.
    static let connectTimeoutSeconds = 10.0

    /// The `limit` for a pass: as many messages as the synchronization limit allows, up to 100.
    static func pageSize(for limits: SyncLimits) throws(ConnectorError) -> Int {
        guard limits.maxItems >= pageSizeRange.lowerBound else {
            throw ConnectorError(.configuration, "the synchronization item limit must be at least 1")
        }
        return min(limits.maxItems, pageSizeRange.upperBound)
    }

    /// The address of one page. `channelID` and the query's snowflake must already be validated.
    static func url(channelID: String, query: DiscordPageQuery, pageSize: Int) -> URL? {
        var parameters = "limit=\(pageSize)"
        switch query {
        case .newest: break
        case .after(let id): parameters += "&after=\(id)"
        case .before(let id): parameters += "&before=\(id)"
        }
        return URL(string: "\(apiBase)/channels/\(channelID)/messages?\(parameters)")
    }

    /// The request for one page, with the documented `Authorization: Bot <token>` and `User-Agent` headers. Redirects are
    /// not followed, and only public internet addresses may be connected to.
    static func make(
        channelID: String, query: DiscordPageQuery, pageSize: Int, token: Sensitive<String>,
        userAgent: DiscordUserAgent, limits: SyncLimits
    ) throws(ConnectorError) -> HTTPRequest {
        let snowflakes: [String]
        switch query {
        case .newest: snowflakes = [channelID]
        case .after(let id), .before(let id): snowflakes = [channelID, id]
        }
        guard snowflakes.allSatisfy(DiscordSnowflake.isValid),
            let url = url(channelID: channelID, query: query, pageSize: pageSize)
        else {
            throw ConnectorError(.internalError, "the Discord request address could not be formed")
        }
        let timeout = Double(min(max(1, limits.timeoutSeconds), 600))
        return HTTPRequest(
            method: "GET", url: url,
            headers: [
                HTTPHeader("Authorization", "Bot \(token.revealed)", sensitive: true),
                HTTPHeader("User-Agent", userAgent.headerValue),
                HTTPHeader("Accept", "application/json"),
            ],
            timeoutSeconds: timeout, connectTimeoutSeconds: min(connectTimeoutSeconds, timeout),
            maxResponseBytes: max(1, min(limits.maxBytes, maxPageBytes)), version: .any, redirects: .none,
            addresses: .publicOnly)
    }
}
