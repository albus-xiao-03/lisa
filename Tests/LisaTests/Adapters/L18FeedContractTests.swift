// Adapter tests for L18, provider contracts, for HTTPS calendar subscriptions and news feeds (CAL-01, CAL-02, NEWS-01,
// INGEST-01, SEC-02; D-41, D-42): the real calendar and feed connectors send their requests through the real libcurl
// client, with TLS verified against a synthetic authority made at run time, to a scripted HTTPS server on loopback
// (LoopbackRedirectClient routes the configured public host there). A full download is a complete snapshot and the
// next request is conditional, so "not modified" changes nothing; an authentication failure (401), a server that
// stops answering (timeout) and a server limiting requests (429 with Retry-After) each fail with their own retry
// class. A private subscription address is a secret: it reaches only the server, never a summary or metadata.

import Foundation
import LisaAPIContract
import LisaCalendarFeeds
import LisaDomain
import LisaHTTP
import LisaNewsFeeds
import LisaPorts
import LisaSecrets
import LisaTime
import Testing

@Suite("L18 — Calendar and news feed contracts", .tags(.adapter))
struct L18FeedContractTests {
    private static let addressVariable = "LISA_TEST_FEED_ADDRESS"
    private static let limits = SyncLimits(maxItems: 10, maxBytes: 1_000_000, timeoutSeconds: 10)

    /// The two document sources that share the conditional-download contract.
    enum Feed: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case calendar
        case news

        var testDescription: String { rawValue }

        var origin: String {
            switch self {
            case .calendar: "https://calendar.example.com"
            case .news: "https://news.example.com"
            }
        }

        var contentType: String {
            switch self {
            case .calendar: "text/calendar; charset=utf-8"
            case .news: "application/rss+xml; charset=utf-8"
            }
        }

        var itemKind: FetchedItemKind {
            switch self {
            case .calendar: .calendar
            case .news: .feed
            }
        }

        var document: Data {
            switch self {
            case .calendar:
                return Data(
                    SyntheticEvent.calendar([
                        SyntheticEvent(
                            uid: "l18-feed@example.com", title: "Synthetic planning", start: "2026-11-16T10:00",
                            end: "2026-11-16T11:00")
                    ]).utf8)
            case .news:
                return Data(
                    """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <rss version="2.0"><channel><title>Synthetic news</title><link>https://news.example.com/</link>
                    <description>Synthetic</description><item><title>Synthetic headline</title>
                    <link>https://news.example.com/a/1</link><guid>l18-feed-1</guid>
                    <pubDate>Mon, 16 Nov 2026 06:00:00 -0500</pubDate></item></channel></rss>
                    """.utf8)
            }
        }

        /// The connector for a private address kept in `secrets`, over `client`, waiting `timeoutSeconds` for an
        /// answer.
        func connector(
            client: any HTTPClient, secrets: any SecretStore, clock: any WallClock, timeoutSeconds: Double
        ) -> any SourceConnector {
            let reference = SecretReference.environment(L18FeedContractTests.addressVariable)
            switch self {
            case .calendar:
                return CalendarSubscriptionConnector(
                    address: .secretURL(reference), secrets: secrets, client: client, clock: clock,
                    options: CalendarSubscriptionOptions(
                        requestTimeoutSeconds: timeoutSeconds, connectTimeoutSeconds: 5))
            case .news:
                return NewsFeedConnector(
                    address: .secretURL(reference), secrets: secrets, client: client, clock: clock,
                    options: NewsFeedOptions(requestTimeoutSeconds: timeoutSeconds, connectTimeoutSeconds: 5))
            }
        }
    }

    /// A feed's connector to a scripted loopback server, with a private address that holds a random token.
    private struct Setup {
        var server: ScriptedHTTPSServer
        var connector: any SourceConnector
        var token: String
        var clock: ManualWallClock
    }

    /// `timeoutSeconds` is short only where the timeout is the point, so a busy machine cannot turn another case into
    /// one.
    private func withSetup(
        _ feed: Feed, timeoutSeconds: Double = 10, _ body: (Setup) async throws -> Void
    ) async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            try await ScriptedHTTPSServer.with(identity: identity) { server in
                let token = SyntheticDevice.randomHex(bytes: 12)
                let secrets = EnvironmentSecretStore(environment: [
                    Self.addressVariable: "\(feed.origin)/private/\(token)/subscription"
                ])
                let clock = TestTime.clock(at: TestTime.instant("2026-11-16T07:00", in: TestTime.newYork))
                let client = try LoopbackRedirectClient(port: server.port, trustStore: identity.authorityFile)
                try await body(
                    Setup(
                        server: server,
                        connector: feed.connector(
                            client: client, secrets: secrets, clock: clock, timeoutSeconds: timeoutSeconds),
                        token: token, clock: clock))
            }
        }
    }

    @Test(
        "Fixture success: a full download is a complete snapshot, and an unchanged document changes nothing",
        arguments: Feed.allCases)
    func downloadsThenRevalidates(_ feed: Feed) async throws {
        try await withSetup(feed) { setup in
            setup.server.script([
                .respond(
                    status: 200,
                    headers: [
                        "Content-Type": feed.contentType, "ETag": "\"synthetic-v1\"",
                        "Last-Modified": "Mon, 16 Nov 2026 11:00:00 GMT",
                    ], body: feed.document),
                .respond(status: 304, headers: ["ETag": "\"synthetic-v1\""]),
            ])
            let full = try await setup.connector.fetch(cursor: nil, limits: Self.limits)
            #expect(full.isCompleteSnapshot)
            #expect(full.items.count == 1)
            let item = try #require(full.items.first)
            #expect(item.kind == feed.itemKind)
            #expect(item.data == feed.document)
            #expect(item.metadata["origin"] == feed.origin)
            #expect(!item.metadata.values.contains { $0.contains(setup.token) })
            #expect(item.receivedAt == setup.clock.now())
            #expect(full.nextCursor != nil)

            setup.clock.advance(by: 600)
            let unchanged = try await setup.connector.fetch(cursor: full.nextCursor, limits: Self.limits)
            // An empty batch that is not a snapshot can never cancel anything the full download held.
            #expect(unchanged.items.isEmpty)
            #expect(!unchanged.isCompleteSnapshot)
            #expect(unchanged.nextCursor != nil)

            let requests = setup.server.requests
            #expect(requests.map(\.method) == [.get, .get])
            #expect(requests.allSatisfy { $0.path == "/private/\(setup.token)/subscription" })
            #expect(requests.allSatisfy { $0.header("Accept-Encoding") == "identity" })
            #expect(requests.first?.header("If-None-Match") == nil)
            #expect(requests.last?.header("If-None-Match") == "\"synthetic-v1\"")
        }
    }

    /// One way the server fails a download.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        var feed: Feed
        var name: String
        var answer: ScriptedHTTPSServer.Answer
        var expected: SourceErrorClass
        /// The retry time the failure must carry, in seconds after the request.
        var retryAfterSeconds: Double?
        var timeoutSeconds: Double = 10
        var testDescription: String { "\(feed.rawValue): \(name)" }
    }

    static let failureCases: [FailureCase] = Feed.allCases.flatMap { feed in
        [
            FailureCase(
                feed: feed, name: "authentication failure (401)", answer: .respond(status: 401),
                expected: .authentication),
            FailureCase(
                feed: feed, name: "timeout: the server stops answering", answer: .hold, expected: .timeout,
                timeoutSeconds: 2),
            FailureCase(
                feed: feed, name: "throttling (429 with Retry-After)",
                answer: .respond(status: 429, headers: ["Retry-After": "120"]), expected: .rateLimited,
                retryAfterSeconds: 120),
        ]
    }

    @Test("Each failure has its own retry class and never shows the private address", arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        try await withSetup(failure.feed, timeoutSeconds: failure.timeoutSeconds) { setup in
            setup.server.script([failure.answer])
            let requested = setup.clock.now()
            let error = try await #require(throws: ConnectorError.self) {
                try await setup.connector.fetch(cursor: nil, limits: Self.limits)
            }
            #expect(error.errorClass == failure.expected, "\(error)")
            #expect(error.errorClass.isRetryable == (failure.expected != .authentication))
            #expect(error.retryAfter == failure.retryAfterSeconds.map { requested.addingTimeInterval($0) })
            #expect(!error.summary.contains(setup.token) && !error.summary.contains("/private/"))
            #expect(setup.server.requests.count == 1)
        }
    }
}
