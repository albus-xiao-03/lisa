// The page-retrieval boundary (NEWS-01, SEC-02): reading the page behind a link the owner captured, on request only.

import Foundation
import LisaDomain

/// The page behind a captured link, as read once at the owner's request.
///
/// The text is what the server gave an anonymous reader, converted to plain text with nothing the page refers to
/// requested; a paywalled or sign-in page yields only its public part. Descriptions and mirrors show only the capture
/// and the text's length, never the address or the content.
public struct CapturedPage: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var captureID: CaptureID
    /// The page's own title, when it has one.
    public var title: String?
    /// The visible text; empty when the page has a title but no text that can be read without scripts.
    public var text: String
    /// Whether the retriever cut the text at its bound.
    public var textTruncated: Bool
    /// The address that produced the page, after any redirects.
    public var finalURL: URL
    /// `text/html`, `application/xhtml+xml` or `text/plain`.
    public var mediaType: String
    /// The page exactly as received, for raw-content retention.
    public var rawContent: Data
    public var retrievedAt: Date

    public init(
        captureID: CaptureID, title: String?, text: String, textTruncated: Bool, finalURL: URL, mediaType: String,
        rawContent: Data, retrievedAt: Date
    ) {
        self.captureID = captureID
        self.title = title
        self.text = text
        self.textTruncated = textTruncated
        self.finalURL = finalURL
        self.mediaType = mediaType
        self.rawContent = rawContent
        self.retrievedAt = retrievedAt
    }

    public var description: String { "captured page for capture \(captureID), \(text.count) characters" }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["page": description]) }
}

/// Reads the page behind a link capture. The application calls it only when the owner, on the host or a paired device,
/// asks for one capture's page; nothing else ever starts a retrieval.
///
/// Implementations:
/// - retrieve only a `link` capture made by the local owner or a paired device, never text, ideas, Apple News shares or
///   anything the runtime, a model or the demonstration captured;
/// - send one GET for the page, to public-internet addresses only, without cookies or credentials, following at most a
///   few redirects that are each re-checked;
/// - never request anything the page refers to (links, images, scripts, styles, frames);
/// - bound the page's size, text and time, and read only HTML, XHTML and plain text.
///
/// Every failure is a classified `ConnectorError` whose summary names at most the origin; nothing is returned for a
/// page that could not be read.
public protocol CapturedPageRetrieval: Sendable {
    func retrieve(_ capture: Capture) async throws(ConnectorError) -> CapturedPage
}
