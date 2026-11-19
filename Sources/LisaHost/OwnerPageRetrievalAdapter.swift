// Adapts the owner-initiated page retriever (LisaNewsFeeds) to the application's captured-page port (NEWS-01, SEC-02).

import Foundation
import LisaDomain
import LisaNewsFeeds
import LisaPorts

/// Reads captured links with `OwnerPageRetriever`. `OwnerPageRequest` admits only an owner-captured https link to a
/// public host, so anything else is refused before a request is made; the retriever then sends one bounded GET.
struct OwnerPageRetrievalAdapter: CapturedPageRetrieval {
    let retriever: OwnerPageRetriever

    func retrieve(_ capture: Capture) async throws(ConnectorError) -> CapturedPage {
        let request = try OwnerPageRequest(capture: capture)
        let page = try await retriever.retrieve(request)
        return CapturedPage(
            captureID: page.captureID, title: page.title, text: page.text, textTruncated: page.textTruncated,
            finalURL: page.finalURL, mediaType: page.mediaType, rawContent: page.rawContent,
            retrievedAt: page.retrievedAt)
    }
}
