// The X account connector: reads one selected account's posts through the official X API v2 with bounded polling.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime

/// Reads the posts of one selected X account (NEWS-02) from `GET /2/users/{id}/tweets` on `https://api.x.com`, with
/// the app-only bearer token of the owner's X developer app. It never reads the owner's home timeline, never writes,
/// and sends nothing but this one read request.
///
/// - **Incremental:** each fetch reads one page of up to `min(limits.maxItems, 100)` posts (X accepts 5 to 100) and
///   returns them oldest first. The cursor is a `since_id` high-water mark; when more than one page of new posts
///   exists, the older pages follow through `pagination_token` in later fetches, and the mark moves only when they
///   are all read (see `XTimelinePosition`). A pagination token X refuses (HTTP 400) restarts that window once from
///   its newest page.
/// - **First synchronization:** only the newest page is read; older history is not imported.
/// - **Rate limits:** a 429, or a response that reports `x-rate-limit-remaining: 0`, blocks further requests until
///   `x-rate-limit-reset`; a 429 can also mean the app's usage cap is used up, which the failure says.
/// - **Failures** are classified and never returned as empty pages: authentication (401), denied access or
///   capabilities (403, protected accounts), unknown or unavailable accounts, rate limits, network, timeout and
///   unreadable responses. Deleted posts simply no longer appear in the timeline; withheld ones are noted.
///
/// The token is resolved from the secret store for every fetch and appears in no error or description.
public struct XAccountConnector: SourceConnector {
    public let kind: SourceKind = .xAccount
    public let configuration: XAccountConfiguration
    private let secrets: any SecretStore
    private let http: any HTTPClient
    private let clock: any WallClock
    private let gate = XRateLimitGate()

    public init(
        configuration: XAccountConfiguration, secrets: any SecretStore, http: any HTTPClient, clock: any WallClock
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
        var position = try XTimelinePosition(cursor: cursor)
        let pageSize = try XTimelineRequest.pageSize(for: limits)
        try Task.checkCancellation()
        try gate.check(now: clock.now())
        let token = try XBearerToken.resolve(configuration.bearerToken, from: secrets)
        var response = try await exchange(position: position, pageSize: pageSize, token: token, limits: limits)
        if response.status == 400, position.window?.next != nil {
            position = position.restartingWindow()
            response = try await exchange(position: position, pageSize: pageSize, token: token, limits: limits)
        }
        let now = clock.now()
        guard response.status == 200 else {
            if response.status == 429 { gate.block(until: XRateLimitHeaders.retryDate(for: response, now: now)) }
            throw XResponseClassifier.failure(for: response, now: now)
        }
        gate.block(until: XRateLimitHeaders(response).exhaustedUntil(now: now))
        let page = try XTimelineDecoder.decode(response.body, pageSize: pageSize)
        if !page.hasData, page.errorCount > 0 {
            throw XResponseClassifier.failure(forErrorsWithoutPosts: page.problems, response: response, now: now)
        }
        let mapped = XPostMapping.items(
            for: page, userID: configuration.userID, after: position.since, fetchedAt: now)
        guard mapped.items.reduce(0, { $0 + $1.data.count }) <= limits.maxBytes else {
            throw ConnectorError(.configuration, "a page of posts from X exceeded the synchronization size limit")
        }
        var notes = mapped.notes
        if page.hasData, page.errorCount > 0 {
            notes.append("X reported problems with some details of these posts; some information may be missing")
        }
        let next = position.advanced(pageIDs: page.posts.map(\.id), nextToken: page.nextToken)
        return FetchBatch(
            items: mapped.items, nextCursor: next.position.encoded, isCompleteSnapshot: false, hasMore: next.hasMore,
            capabilityNotes: notes)
    }

    /// One request for the page at `position`; transport failures are classified here.
    private func exchange(
        position: XTimelinePosition, pageSize: Int, token: Sensitive<String>, limits: SyncLimits
    ) async throws -> HTTPResponse {
        let request = try XTimelineRequest.make(
            userID: configuration.userID, position: position, pageSize: pageSize, token: token, limits: limits)
        do {
            return try await http.send(request)
        } catch {
            throw XTransportFailureMapping.error(for: error)
        }
    }
}
