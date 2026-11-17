// The Discord channel connector: reads one configured channel's messages through the REST API with a bot token.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime

/// Reads the messages of one explicitly configured channel (NEWS-03) from `GET /channels/{id}/messages` on Discord's
/// v10 REST API, as the owner's authorized bot (`Authorization: Bot <token>`). It never uses a user account token,
/// never posts or reacts, and sends nothing but this one read request.
///
/// - **Incremental:** each fetch reads one page of up to `min(limits.maxItems, 100)` messages and returns the new ones
///   oldest first. The cursor is an `after` snowflake; a full page is followed by pages read backwards with `before`
///   until they meet the cursor, so no message is skipped (see `DiscordChannelPosition`).
/// - **First synchronization:** only the newest page is read; older history is not imported.
/// - **Message content:** Discord withholds `content`, `embeds`, `attachments` and `components` from bots without the
///   `MESSAGE_CONTENT` privileged intent, in REST responses too. Such messages are never stored as empty posts: they
///   are skipped with a capability note, and a page in which nothing could be read fails as `capabilityDenied`,
///   which tells the owner that automatic monitoring is unavailable and the manual capture route remains.
/// - **Permissions:** 403 (no View Channel) fails as `permissionDenied`. Without Read Message History Discord returns
///   no messages at all, which looks like an empty channel; the first synchronization notes this possibility.
/// - **Rate limits:** a 429, or a response whose bucket has no requests remaining, blocks further requests until the
///   reset Discord reports, because 429 responses count toward its invalid-request limit.
///
/// The token is resolved from the secret store for every fetch and appears in no error or description.
public struct DiscordChannelConnector: SourceConnector {
    public let kind: SourceKind = .discordChannel
    public let configuration: DiscordChannelConfiguration
    private let secrets: any SecretStore
    private let http: any HTTPClient
    private let clock: any WallClock
    private let gate = DiscordRateLimitGate()

    public init(
        configuration: DiscordChannelConfiguration, secrets: any SecretStore, http: any HTTPClient,
        clock: any WallClock
    ) {
        self.configuration = configuration
        self.secrets = secrets
        self.http = http
        self.clock = clock
    }

    public func validateConfiguration() throws {
        try configuration.validate()
    }

    public func fetch(cursor: String?, limits: SyncLimits) async throws -> FetchBatch {
        try configuration.validate()
        let position = try DiscordChannelPosition(cursor: cursor)
        let pageSize = try DiscordMessagesRequest.pageSize(for: limits)
        try Task.checkCancellation()
        try gate.check(now: clock.now())
        let token = try DiscordBotToken.resolve(configuration.botToken, from: secrets)
        let request = try DiscordMessagesRequest.make(
            channelID: configuration.channelID, query: position.query, pageSize: pageSize, token: token,
            userAgent: configuration.userAgent, limits: limits)
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw DiscordTransportFailureMapping.error(for: error)
        }
        let now = clock.now()
        guard response.status == 200 else {
            if response.status == 429 {
                gate.block(
                    until: DiscordRateLimitHeaders.retryDate(
                        for: response, body: DiscordErrorBody.parse(response.body), now: now))
            }
            throw DiscordResponseClassifier.failure(for: response, now: now)
        }
        gate.block(until: DiscordRateLimitHeaders(response).exhaustedUntil(now: now))
        let page = try DiscordMessagePage.decode(response.body, pageSize: pageSize)
        let next = try position.advanced(pageIDs: page.snowflakes, pageSize: pageSize)
        let fresh = page.messages.filter { position.isNew($0.snowflake) }
        let mapped = DiscordMessageMapping.map(fresh, channelID: configuration.channelID)
        if mapped.withheld > 0, mapped.readable == 0 {
            throw ConnectorError(.capabilityDenied, DiscordMessageMapping.Note.monitoringUnavailable)
        }
        guard mapped.items.reduce(0, { $0 + $1.data.count }) <= limits.maxBytes else {
            throw ConnectorError(
                .configuration, "a page of messages from Discord exceeded the synchronization size limit")
        }
        var notes = mapped.notes
        if position.isInitial, page.messages.isEmpty { notes.append(DiscordMessageMapping.Note.emptyFirstRead) }
        return FetchBatch(
            items: mapped.items, nextCursor: next.position.encoded, isCompleteSnapshot: false, hasMore: next.hasMore,
            capabilityNotes: notes)
    }
}
