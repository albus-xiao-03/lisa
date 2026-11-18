// Adapter tests for L18, provider contracts, for X (NEWS-02, INGEST-01, SEC-01; D-42): the real X account connector
// runs against a scripted transport at the LisaHTTP boundary. Success reads one page of the account's posts, oldest
// first, with links and publication times, using the app bearer token from the secret store, and the next request
// asks only for newer posts; an authentication failure (401) and a timeout are classified; throttling (429 with the
// window's reset time) blocks every request until the reset, so none is sent early. Nothing reaches X.

import Foundation
import LisaDomain
import LisaHTTP
import LisaPorts
import LisaSecrets
import LisaTime
import LisaXSource
import Testing

@Suite("L18 — X account contract", .tags(.adapter))
struct L18XContractTests {
    private static let userID = "2244994945"
    private static let tokenVariable = "LISA_TEST_X_TOKEN"
    private static let limits = SyncLimits(maxItems: 20, maxBytes: 1_000_000, timeoutSeconds: 30)

    private static let page = Data(
        """
        {"data":[
        {"id":"1858000000000000002","text":"Second synthetic post","created_at":"2026-11-16T11:00:00.000Z"},
        {"id":"1858000000000000001","text":"First synthetic post","created_at":"2026-11-16T10:00:00.000Z"}],
        "includes":{"users":[{"id":"2244994945","username":"synthetic_news"}]},
        "meta":{"newest_id":"1858000000000000002","oldest_id":"1858000000000000001","result_count":2}}
        """.utf8)

    private struct Setup {
        var client: ScriptedHTTPClient
        var connector: XAccountConnector
        var token: String
        var clock: ManualWallClock
    }

    private func setup(_ steps: [ScriptedHTTPClient.Step]) -> Setup {
        let client = ScriptedHTTPClient(steps)
        let token = SyntheticDevice.randomHex(bytes: 24)
        let clock = TestTime.clock(at: TestTime.instant("2026-11-16T07:00", in: TestTime.newYork))
        let connector = XAccountConnector(
            configuration: XAccountConfiguration(userID: Self.userID, bearerToken: .environment(Self.tokenVariable)),
            secrets: EnvironmentSecretStore(environment: [Self.tokenVariable: token]), http: client, clock: clock)
        return Setup(client: client, connector: connector, token: token, clock: clock)
    }

    private static func query(_ request: HTTPRequest) -> [String: String] {
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    @Test("Fixture success: posts arrive oldest first with links and times, and the next request asks for newer ones")
    func readsPostsIncrementally() async throws {
        let empty = Data(#"{"meta":{"result_count":0}}"#.utf8)
        let setup = setup([.respond(status: 200, body: Self.page), .respond(status: 200, body: empty)])
        let batch = try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        #expect(batch.items.map(\.externalID) == ["x:1858000000000000001", "x:1858000000000000002"])
        let texts = batch.items.map { String(decoding: $0.data, as: UTF8.self) }
        #expect(texts == ["First synthetic post", "Second synthetic post"])
        #expect(batch.items.allSatisfy { $0.kind == .post })
        #expect(
            batch.items.map { $0.metadata["url"] } == [
                "https://x.com/synthetic_news/status/1858000000000000001",
                "https://x.com/synthetic_news/status/1858000000000000002",
            ])
        #expect(batch.items.first?.receivedAt == TestTime.utcInstant("2026-11-16T10:00"))
        #expect(!batch.isCompleteSnapshot)
        #expect(!batch.hasMore)

        let newer = try await setup.connector.fetch(cursor: batch.nextCursor, limits: Self.limits)
        #expect(newer.items.isEmpty)

        let requests = setup.client.requests
        #expect(requests.count == 2)
        for request in requests {
            #expect(request.method == "GET")
            #expect(request.url.host == "api.x.com")
            #expect(request.url.path == "/2/users/\(Self.userID)/tweets")
            #expect(request.addresses == .publicOnly)
            #expect(request.redirects == .none)
            let authorization = try #require(request.headers.first { $0.name.lowercased() == "authorization" })
            #expect(authorization.value == "Bearer \(setup.token)")
            #expect(authorization.isSensitive)
            #expect(!"\(request)".contains(setup.token))
        }
        #expect(Self.query(requests[0])["since_id"] == nil)
        #expect(Self.query(requests[1])["since_id"] == "1858000000000000002")
    }

    @Test("An authentication failure is not retried automatically, and the token never appears in the failure")
    func authenticationFailure() async throws {
        let setup = setup([.respond(status: 401, body: Data(#"{"title":"Unauthorized","status":401}"#.utf8))])
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

    @Test("Throttling blocks every request until the window resets, then reading resumes")
    func throttlingIsHonored() async throws {
        let setup = setup([])
        let reset = setup.clock.now().addingTimeInterval(900)
        setup.client.script([
            .respond(
                status: 429,
                headers: [
                    HTTPHeader("x-rate-limit-remaining", "0"),
                    HTTPHeader("x-rate-limit-reset", String(Int(reset.timeIntervalSince1970))),
                ], body: Data(#"{"title":"Too Many Requests","status":429}"#.utf8)),
            .respond(status: 200, body: Self.page),
        ])
        let throttled = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(throttled.errorClass == .rateLimited)
        #expect(throttled.retryAfter == reset)

        // Before the reset nothing is sent; the connector answers from its own record of the window.
        setup.clock.advance(by: 600)
        let early = try await #require(throws: ConnectorError.self) {
            try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        }
        #expect(early.errorClass == .rateLimited)
        #expect(early.retryAfter == reset)
        #expect(setup.client.requests.count == 1)

        setup.clock.set(reset.addingTimeInterval(1))
        let resumed = try await setup.connector.fetch(cursor: nil, limits: Self.limits)
        #expect(resumed.items.count == 2)
        #expect(setup.client.requests.count == 2)
    }
}
