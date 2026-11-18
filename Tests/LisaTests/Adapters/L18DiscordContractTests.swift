// Adapter tests for L18, provider contracts, for Discord (NEWS-03, INGEST-01, SEC-01; D-42): the real Discord channel
// connector runs against a scripted transport at the LisaHTTP boundary. Success reads one page of the channel's
// messages, oldest first, as the owner's bot with Discord's required User-Agent, and the next request asks only for
// newer messages; an authentication failure (401) and a timeout are classified; throttling (429 with Discord's retry
// time) blocks every request until then, because rate-limited requests count toward Discord's invalid-request limit.
// Nothing reaches Discord, and nothing is ever posted.

import Foundation
import LisaDiscordSource
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaSecrets
import LisaTime
import Testing

@Suite("L18 — Discord channel contract", .tags(.adapter))
struct L18DiscordContractTests {
    private static let channelID = "1100000000000000001"
    private static let tokenVariable = "LISA_TEST_DISCORD_TOKEN"
    private static let limits = SyncLimits(maxItems: 20, maxBytes: 1_000_000, timeoutSeconds: 30)

    private static let page = Data(
        """
        [{"id":"1100000000000000012","type":0,"timestamp":"2026-11-16T11:00:00.000000+00:00",
          "author":{"id":"1100000000000000099","username":"synthetic_member"},"content":"Second synthetic message"},
         {"id":"1100000000000000011","type":0,"timestamp":"2026-11-16T10:00:00.000000+00:00",
          "author":{"id":"1100000000000000099","username":"synthetic_member"},"content":"First synthetic message"}]
        """.utf8)

    private struct Setup {
        var client: ScriptedHTTPClient
        var connector: DiscordChannelConnector
        var token: String
        var clock: ManualWallClock
    }

    private func setup(_ steps: [ScriptedHTTPClient.Step]) -> Setup {
        let client = ScriptedHTTPClient(steps)
        let token = SyntheticDevice.randomHex(bytes: 24)
        let clock = TestTime.clock(at: TestTime.instant("2026-11-16T07:00", in: TestTime.newYork))
        let configuration = DiscordChannelConfiguration(
            channelID: Self.channelID, botToken: .environment(Self.tokenVariable),
            userAgent: DiscordUserAgent(version: "0.0.0-test"))
        let connector = DiscordChannelConnector(
            configuration: configuration, secrets: EnvironmentSecretStore(environment: [Self.tokenVariable: token]),
            http: client, clock: clock)
        return Setup(client: client, connector: connector, token: token, clock: clock)
    }

    private static func query(_ request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test(
        "Fixture success: messages arrive oldest first as the bot reads them, and the next request asks for newer ones")
    func readsMessagesIncrementally() async throws {
        let setup = setup([.respond(status: 200, body: Self.page), .respond(status: 200, body: Data("[]".utf8))])
        let batch = try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        #expect(
            batch.items.map(\.externalID) == [
                "discord:\(Self.channelID):1100000000000000011", "discord:\(Self.channelID):1100000000000000012",
            ])
        let texts = batch.items.map { String(decoding: $0.data, as: UTF8.self) }
        #expect(texts == ["First synthetic message", "Second synthetic message"])
        #expect(batch.items.first?.metadata["title"] == "synthetic_member: First synthetic message")
        #expect(batch.items.first?.receivedAt == TestTime.utcInstant("2026-11-16T10:00"))
        #expect(!batch.isCompleteSnapshot)

        let newer = try await setup.connector.fetch(cursor: batch.nextCursor, limits: Self.limits)
        #expect(newer.items.isEmpty)

        let requests = setup.client.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.method == "GET")
            #expect(request.url.host == "discord.com")
            #expect(request.url.path == "/api/v10/channels/\(Self.channelID)/messages")
            #expect(request.addresses == .publicOnly)
            #expect(request.redirects == .none)
            #expect(request.header("User-Agent") == "DiscordBot (https://lisa.invalid, 0.0.0-test)")
            let authorization = try #require(request.headers.first { $0.name.lowercased() == "authorization" })
            #expect(authorization.value == "Bot \(setup.token)")
            #expect(authorization.isSensitive)
            #expect(!"\(request)".contains(setup.token))
        }
        #expect(Self.query(requests[0])["after"] == nil)
        #expect(Self.query(requests[1])["after"] == "1100000000000000012")
    }

    @Test("An authentication failure is not retried automatically, and the token never appears in the failure")
    func authenticationFailure() async throws {
        let setup = setup([.respond(status: 401, body: Data(#"{"message":"401: Unauthorized","code":0}"#.utf8))])
        let error = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(error.errorClass == .authentication)
        #expect(!error.errorClass.isRetryable)
        #expect(!error.description.contains(setup.token))
    }

    @Test("A timeout is classified as one, whether or not the request was sent", arguments: [true, false])
    func timeout(requestSent: Bool) async throws {
        let setup = setup([.fail(.timedOut(requestSent: requestSent))])
        let error = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(error.errorClass == .timeout)
        #expect(error.errorClass.isRetryable)
    }

    @Test("Throttling blocks every request until Discord's retry time, then reading resumes")
    func throttlingIsHonored() async throws {
        let setup = setup([
            .respond(
                status: 429,
                headers: [
                    HTTPHeader("Retry-After", "30"), HTTPHeader("X-RateLimit-Remaining", "0"),
                    HTTPHeader("X-RateLimit-Reset-After", "30.5"), HTTPHeader("X-RateLimit-Scope", "user"),
                ], body: Data(#"{"message":"You are being rate limited.","retry_after":30.5,"global":false}"#.utf8)),
            .respond(status: 200, body: Self.page),
        ])
        let start = setup.clock.now()
        let throttled = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(throttled.errorClass == .rateLimited)
        #expect(throttled.retryAfter == start.addingTimeInterval(30.5))

        setup.clock.advance(by: 20)
        let early = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(early.errorClass == .rateLimited)
        #expect(setup.client.requests.count == 1)

        setup.clock.advance(by: 11)
        let resumed = try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        #expect(resumed.items.count == 2)
        #expect(setup.client.requests.count == 2)
    }
}
