// Integration tests for NEWS-04, shared Apple News (NEWS-04, with NEWS-01, BRIEF-01 and BRIEF-02; D-31, D-46,
// docs/API.md): Apple News links, and Apple News shares that carry text, captured through the API by a paired companion
// become shared news items under the owner's shared source, marked as coming from Apple News, while other shared text
// is not marked so. Sharing the same address again, from any of the owner's devices, links to the same item. Apple News
// items are never fetched: a request to read one is refused with 409 as docs/API.md describes, an Apple News address
// captured as an ordinary link is not read either, and nothing reaches the network, while an ordinary link the owner
// captured does reach it. The brief lists a shared story as shared by the owner and headline only, and does not present
// the owner's shares as a source that could not be checked. The host's network is a recording, test-only HTTP client at
// the LisaHTTP boundary that sends nothing; every other client is refused.

import Foundation
import LisaAPI
import LisaAPIContract
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaSecrets
import Testing

@Suite("NEWS-04 — Shared Apple News", .tags(.integration))
struct NEWS04SharedAppleNewsTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    /// A synthetic Apple News share address and the title the share sheet supplies with it.
    private static let storyURL = "https://apple.news/ASyntheticTransitStory"
    private static let storyTitle = "Synthetic transit plan approved"

    /// The production host with a paired iPhone. The captured-page reader's HTTP client is `connectors`.
    private struct Setup {
        let host: LisaHost
        /// Records every request and answers none of them; nothing is sent anywhere.
        let connectors: ScriptedHTTPClient
        /// The paired iPhone's device credential.
        let phoneCredential: String
    }

    /// Opens the host over a scratch data directory with `interests` as the owner's news interests, and pairs a
    /// synthetic iPhone with a one-time code, as the companion does.
    private func setUp(_ scratch: ScratchDirectory, interests: [String] = []) throws -> Setup {
        var owner = TestHost.owner()
        owner.newsInterests = interests
        let testHost = TestHost(scratch: scratch, now: start, owner: owner)
        let connectors = ScriptedHTTPClient()
        let network = HostNetwork(
            makeHTTPClient: { purpose in
                if case .connectors = purpose { return connectors }
                throw TestHost.NetworkRefused(purpose: purpose)
            }, mailTrustStorePath: nil, library: TestHost.offlineNetwork.library)
        let host = try LisaHost.open(
            settings: testHost.settings,
            platform: HostPlatform(
                clock: testHost.clock, secrets: EnvironmentSecretStore(environment: [:]), mode: "test",
                network: network))
        let app = host.application
        let code = try app.createPairingCode(by: .localOwner)
        let issued = try app.pairDevice(
            code: code.code, installationID: SyntheticDevice.randomHex(bytes: 16), name: "Synthetic iPhone",
            deviceClass: .iPhone, appBundleID: SyntheticDevice.companionBundleID, environment: .development)
        return Setup(host: host, connectors: connectors, phoneCredential: issued.credential)
    }

    /// `route` sent by the paired iPhone with its credential, as the network server routes it.
    private func asPhone(
        _ setup: Setup, _ route: APIRoute, query: [String: String] = [:], body: Data? = nil, requestID: String? = nil
    ) async -> APIResponse {
        await setup.host.router.handle(
            APIExchange.request(
                route, query: query, body: body, requestID: requestID, credential: setup.phoneCredential),
            origin: .authenticateHeaders(isLoopback: true))
    }

    /// `route` sent by the owner on the host, as the Mac app and the CLI do.
    private func asOwner(_ setup: Setup, _ route: APIRoute, body: Data? = nil, requestID: String? = nil) async
        -> APIResponse
    {
        await setup.host.router.handle(
            APIExchange.request(route, body: body, requestID: requestID), origin: .trustedLocalOwner)
    }

    /// A capture request body.
    private func capture(
        _ kind: CaptureKindValue, url: String?, text: String? = nil, title: String? = nil,
        channel: CaptureChannelValue = .nativeApp
    ) throws -> Data {
        try APIExchange.json(CaptureRequestDTO(kind: kind, text: text, url: url, title: title, channel: channel))
    }

    /// The created capture in `response`, which must be a `201`.
    private func created(_ response: APIResponse, sourceLocation: SourceLocation = #_sourceLocation) throws
        -> CaptureDTO
    {
        #expect(response.status == 201, sourceLocation: sourceLocation)
        let dto = try APIExchange.decode(CaptureDTO.self, response)
        #expect(dto.created, sourceLocation: sourceLocation)
        return dto
    }

    /// The news item `capture` produced.
    private func item(_ setup: Setup, _ capture: CaptureDTO) throws -> NewsItem {
        let id = try #require(capture.newsID)
        return try #require(try setup.host.application.record(NewsItem.self, id: NewsID(id)))
    }

    @Test("Apple News links and shared text from the companion become shared items marked as coming from Apple News")
    func sharesBecomeSharedItems() async throws {
        try await ScratchDirectory.with { scratch in
            let setup = try setUp(scratch)
            defer { setup.host.close() }
            let app = setup.host.application

            // A story shared from Apple News on the iPhone: its link and its title.
            let link = try created(
                await asPhone(
                    setup, .capture, body: try capture(.sharedAppleNews, url: Self.storyURL, title: Self.storyTitle),
                    requestID: "news04-share-link-0001"))
            #expect(link.kind == .sharedAppleNews)
            #expect(link.ideaID == nil)
            let linkItem = try item(setup, link)
            #expect(linkItem.isSharedContent)
            #expect(linkItem.sharedFrom == "Apple News")
            #expect(linkItem.originalURL == Self.storyURL)
            #expect(linkItem.title == Self.storyTitle)
            // Only the link was shared, so the item stays headline only: nothing was read.
            #expect(linkItem.boundary == .titleOnly)
            #expect(linkItem.accessibleText == nil)
            #expect(linkItem.pageURL == nil)

            // It belongs to the owner's shared source, and its evidence leads back to the capture.
            let source = try #require(try app.record(Source.self, id: linkItem.sourceID))
            #expect(source.kind == .manualCapture)
            #expect(source.configurationKey == CaptureService.manualSourceKey)
            #expect(source.name == "Shared by the owner")
            let evidence = try #require(try app.record(Evidence.self, id: linkItem.evidenceID))
            #expect(evidence.kind == .capture)
            #expect(evidence.externalID == link.id)
            #expect(evidence.sourceID == source.id)

            // A story shared with the text the owner selected keeps that text as shared text.
            let excerpt = "Synthetic excerpt: the city approved a new light-rail line along the river."
            let shared = try created(
                await asPhone(
                    setup, .capture,
                    body: try capture(.sharedAppleNews, url: "https://apple.news/ASyntheticRailStory", text: excerpt),
                    requestID: "news04-share-text-0001"))
            let sharedItem = try item(setup, shared)
            #expect(sharedItem.isSharedContent)
            #expect(sharedItem.sharedFrom == "Apple News")
            #expect(sharedItem.boundary == .sharedText)
            #expect(sharedItem.accessibleText == excerpt)
            #expect(sharedItem.sourceID == source.id)

            // Other shared text is shared content in the same source, but not marked as coming from Apple News.
            let text = try created(
                await asPhone(
                    setup, .capture, body: try capture(.text, url: nil, text: "Synthetic note about bus lanes"),
                    requestID: "news04-share-plain-0001"))
            let textItem = try item(setup, text)
            #expect(textItem.isSharedContent)
            #expect(textItem.sharedFrom == nil)
            #expect(textItem.sourceID == source.id)

            let fromAppleNews = try app.all(NewsItem.self).filter { $0.sharedFrom == "Apple News" }
            #expect(Set(fromAppleNews.map(\.id)) == [linkItem.id, sharedItem.id])
        }
    }

    @Test("Sharing the same Apple News address again, from any of the owner's devices, links to the same item")
    func sameAddressLinksToTheSameItem() async throws {
        try await ScratchDirectory.with { scratch in
            let setup = try setUp(scratch)
            defer { setup.host.close() }
            let app = setup.host.application
            let first = try created(
                await asPhone(
                    setup, .capture, body: try capture(.sharedAppleNews, url: Self.storyURL, title: Self.storyTitle),
                    requestID: "news04-same-0001"))
            let original = try item(setup, first)

            // The same address with its scheme and host in capitals and a fragment, shared again from the iPhone.
            let again = try created(
                await asPhone(
                    setup, .capture,
                    body: try capture(.sharedAppleNews, url: "HTTPS://APPLE.NEWS/ASyntheticTransitStory#comments"),
                    requestID: "news04-same-0002"))
            // The same address shared by the owner on the Mac, with another title.
            let fromMac = try created(
                await asOwner(
                    setup, .capture,
                    body: try capture(
                        .sharedAppleNews, url: Self.storyURL, title: "Another title", channel: .commandLine),
                    requestID: "news04-same-0003"))
            // Each share is its own capture, linked to the one item, which keeps what the first share supplied.
            #expect(Set([first.id, again.id, fromMac.id]).count == 3)
            #expect(again.newsID == first.newsID)
            #expect(fromMac.newsID == first.newsID)
            let linked = try item(setup, fromMac)
            #expect(linked.title == Self.storyTitle)
            #expect(linked.originalURL == Self.storyURL)
            #expect(linked.revision == original.revision)
            #expect(try app.all(NewsItem.self).filter { $0.sourceID == original.sourceID }.count == 1)

            // An address that differs in its path, here only in the case of its letters, is another story.
            let otherURL = "https://apple.news/Asynthetictransitstory"
            let other = try created(
                await asPhone(
                    setup, .capture, body: try capture(.sharedAppleNews, url: otherURL), requestID: "news04-same-0004"))
            #expect(other.newsID != first.newsID)
            #expect(try app.all(NewsItem.self).filter { $0.sourceID == original.sourceID }.count == 2)
        }
    }

    @Test("Apple News items are never fetched: reading one is refused with 409, and nothing reaches the network")
    func appleNewsItemsAreNeverFetched() async throws {
        try await ScratchDirectory.with { scratch in
            let setup = try setUp(scratch)
            defer { setup.host.close() }
            let share = try created(
                await asPhone(
                    setup, .capture, body: try capture(.sharedAppleNews, url: Self.storyURL, title: Self.storyTitle),
                    requestID: "news04-fetch-share-0001"))
            let before = try item(setup, share)

            // The iPhone and the owner on the Mac each ask to read it: both are refused as a conflict, which names
            // the reason.
            let phoneRead = await asPhone(setup, .retrieveCapture(id: share.id), requestID: "news04-fetch-phone-0001")
            let refusal = APIExchange.expectError(phoneRead, .conflict)
            #expect(refusal?.message.contains("Apple News") == true)
            let ownerRead = await asOwner(setup, .retrieveCapture(id: share.id), requestID: "news04-fetch-owner-0001")
            APIExchange.expectError(ownerRead, .conflict)
            // A runtime cycle does not read it either.
            _ = await setup.host.runtime.runOnce()
            #expect(setup.connectors.requests.isEmpty)
            // The item is as it was: headline only and never read.
            let after = try item(setup, share)
            #expect(after.boundary == .titleOnly)
            #expect(after.accessibleText == nil)
            #expect(after.pageURL == nil)
            #expect(after.revision == before.revision)

            // An Apple News address captured as an ordinary link is not read either: the answer says why, and the item
            // is left as it was.
            let asLink = try created(
                await asOwner(
                    setup, .capture,
                    body: try capture(.link, url: "https://apple.news/ASyntheticHousingStory", channel: .commandLine),
                    requestID: "news04-fetch-link-0001"))
            let linkRead = await asOwner(setup, .retrieveCapture(id: asLink.id), requestID: "news04-fetch-link-0002")
            #expect(linkRead.status == 200)
            let retrieval = try APIExchange.decode(CaptureRetrievalDTO.self, linkRead)
            #expect(!retrieval.retrieved)
            #expect(retrieval.failureClass == "unsupported")
            #expect(retrieval.boundary == "titleOnly")
            #expect(retrieval.pageURL == nil)
            #expect(setup.connectors.requests.isEmpty)

            // The same host does try to read an ordinary link the owner captured: its one request reaches the
            // recording client, which sends nothing, so the answer is a temporary failure to retry later.
            let ordinary = try created(
                await asOwner(
                    setup, .capture,
                    body: try capture(.link, url: "https://news.example.com/synthetic-transit", channel: .commandLine),
                    requestID: "news04-fetch-ordinary-0001"))
            let ordinaryRead = await asOwner(
                setup, .retrieveCapture(id: ordinary.id), requestID: "news04-fetch-ordinary-0002")
            let temporary = APIExchange.expectError(ordinaryRead, .unavailable)
            #expect(temporary?.retryAfterSeconds == CapturedPageService.defaultRetrySeconds)
            let requests = setup.connectors.requests
            #expect(requests.map(\.method) == ["GET"])
            #expect(requests.map(\.url.absoluteString) == ["https://news.example.com/synthetic-transit"])
        }
    }

    /// Shares the synthetic transit story from the iPhone and returns the brief the iPhone then reads, with the item.
    private func briefAfterSharing(_ setup: Setup) async throws -> (brief: BriefDTO, newsID: String) {
        let share = try created(
            await asPhone(
                setup, .capture, body: try capture(.sharedAppleNews, url: Self.storyURL, title: Self.storyTitle),
                requestID: "news04-brief-share-0001"))
        let newsID = try #require(share.newsID)
        let response = await asPhone(setup, .brief, query: ["date": "2026-11-16"])
        #expect(response.status == 200)
        return (try APIExchange.decode(BriefDTO.self, response), newsID)
    }

    @Test("The brief lists a shared Apple News story as shared by the owner and headline only, in both versions")
    func briefLabelsTheSharedStory() async throws {
        try await ScratchDirectory.with { scratch in
            let setup = try setUp(scratch, interests: ["transit"])
            defer { setup.host.close() }
            let (brief, newsID) = try await briefAfterSharing(setup)
            let line = try #require(
                brief.items.first { item in
                    item.section == "news" && item.references.contains { $0.recordID == newsID }
                })
            #expect(line.text.contains(Self.storyTitle))
            #expect(line.text.contains("(headline only)"))
            #expect(line.text.contains("(shared by you)"))
            #expect(line.references.contains { $0.recordKind == "news" && $0.originalURL == Self.storyURL })
            #expect(brief.text.contains(line.text))
            // The spoken line names the story and says only its headline is known, without the link.
            #expect(line.spokenText.contains(Self.storyTitle))
            #expect(line.spokenText.contains("headline only"))
            #expect(brief.spokenText.contains(line.spokenText))
            #expect(!brief.spokenText.contains("apple.news"))
            #expect(setup.connectors.requests.isEmpty)
        }
    }

    @Test("After the owner shares a story, the brief does not report the owner's shares as a source it could not check")
    func briefDoesNotReportSharesAsUnchecked() async throws {
        try await ScratchDirectory.with { scratch in
            let setup = try setUp(scratch, interests: ["transit"])
            defer { setup.host.close() }
            let (brief, _) = try await briefAfterSharing(setup)
            // Shares arrive only when the owner shares something; there is nothing to check, so the brief must not warn
            // that the owner's shares could not be checked (BRIEF-01; D-18: "Could not check" is for failing or stale
            // sources).
            #expect(!brief.text.contains("Could not check Shared by the owner"))
            #expect(!brief.spokenText.contains("I could not check Shared by the owner"))
            #expect(!brief.items.contains { $0.section == "sourceHealth" && $0.text.contains("Shared by the owner") })
        }
    }
}
