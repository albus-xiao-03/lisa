// Adapter tests for L18, provider contracts, for reading a link the owner captured (NEWS-01, SEC-02; D-46): the real
// page retriever sends one GET through the real libcurl client, with TLS verified against a synthetic authority made
// at run time, to a scripted HTTPS server on loopback (LoopbackRedirectClient routes the captured public host there).
// Success reads the page as text, without scripts, and never requests anything the page refers to; a page that needs
// signing in (401), a server that stops answering (timeout) and a server limiting requests (429 with Retry-After)
// each fail with their own class, so the item stays title-only and says why. Nothing outside this machine is reached.

import Foundation
import LisaAPIContract
import LisaDomain
import LisaNewsFeeds
import LisaPorts
import LisaTime
import Testing

@Suite("L18 — Captured link retrieval contract", .tags(.adapter))
struct L18CapturedPageContractTests {
    private static let link = "https://news.example.com/articles/synthetic-story"

    private static let page = Data(
        """
        <!doctype html><html><head><title>Synthetic story</title>
        <script>document.write("never run")</script><link rel="stylesheet" href="/style.css"></head>
        <body><h1>Synthetic story</h1><p>The first synthetic paragraph.</p><img src="/picture.png">
        <p>The second synthetic paragraph.</p><iframe src="https://elsewhere.example.com/frame"></iframe></body></html>
        """.utf8)

    private struct Setup {
        var server: ScriptedHTTPSServer
        var retriever: OwnerPageRetriever
        var request: OwnerPageRequest
        var clock: ManualWallClock
    }

    /// `timeoutSeconds` is short only where the timeout is the point, so a busy machine cannot turn another case into
    /// one.
    private func withSetup(timeoutSeconds: Double = 10, _ body: (Setup) async throws -> Void) async throws {
        try await ScratchDirectory.with { scratch in
            let identity = try await SyntheticTLSIdentity.generate(in: scratch.path("tls"))
            try await ScriptedHTTPSServer.with(identity: identity) { server in
                let clock = TestTime.clock(at: TestTime.instant("2026-11-16T07:00", in: TestTime.newYork))
                let capture = Capture(
                    kind: .link, text: nil, url: Self.link, channel: .commandLine, principal: .localOwner,
                    requestID: nil, now: clock.now())
                let retriever = OwnerPageRetriever(
                    client: try LoopbackRedirectClient(port: server.port, trustStore: identity.authorityFile),
                    clock: clock, options: OwnerPageOptions(timeoutSeconds: timeoutSeconds, connectTimeoutSeconds: 5))
                try await body(
                    Setup(
                        server: server, retriever: retriever, request: try OwnerPageRequest(capture: capture),
                        clock: clock))
            }
        }
    }

    @Test("Fixture success: one request reads the page as text, without scripts and without anything it refers to")
    func readsThePageAsText() async throws {
        try await withSetup { setup in
            setup.server.script([
                .respond(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: Self.page)
            ])
            let page = try await setup.retriever.retrieve(setup.request)
            #expect(page.title == "Synthetic story")
            #expect(page.text.contains("The first synthetic paragraph."))
            #expect(page.text.contains("The second synthetic paragraph."))
            #expect(!page.text.contains("never run"))
            #expect(page.finalURL.absoluteString == Self.link)
            #expect(page.retrievedAt == setup.clock.now())
            let requests = setup.server.requests
            #expect(requests.map(\.path) == ["/articles/synthetic-story"])
            #expect(requests.first?.method == .get)
            #expect(requests.first?.header("Authorization") == nil && requests.first?.header("Cookie") == nil)
        }
    }

    /// One way the site fails the retrieval.
    struct FailureCase: Sendable, CustomTestStringConvertible {
        var name: String
        var answer: ScriptedHTTPSServer.Answer
        var expected: SourceErrorClass
        var retryAfterSeconds: Double?
        var timeoutSeconds: Double = 10
        var testDescription: String { name }
    }

    static let failureCases: [FailureCase] = [
        FailureCase(
            name: "authentication: the page needs signing in (401)", answer: .respond(status: 401),
            expected: .authentication),
        FailureCase(
            name: "timeout: the server stops answering", answer: .hold, expected: .timeout, timeoutSeconds: 2),
        FailureCase(
            name: "throttling (429 with Retry-After)", answer: .respond(status: 429, headers: ["Retry-After": "60"]),
            expected: .rateLimited, retryAfterSeconds: 60),
    ]

    @Test("Each failure has its own class, so the item stays title-only and says why", arguments: failureCases)
    func failuresAreClassified(_ failure: FailureCase) async throws {
        try await withSetup(timeoutSeconds: failure.timeoutSeconds) { setup in
            setup.server.script([failure.answer])
            let requested = setup.clock.now()
            let error = try await #require(throws: ConnectorError.self) {
                try await setup.retriever.retrieve(setup.request)
            }
            #expect(error.errorClass == failure.expected, "\(error)")
            #expect(error.retryAfter == failure.retryAfterSeconds.map { requested.addingTimeInterval($0) })
            #expect(setup.server.requests.count == 1)
        }
    }
}
