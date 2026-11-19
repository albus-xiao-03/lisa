// The result of an owner-initiated page retrieval: the page's visible text and title, what was read, and when.

import Foundation
import LisaDomain
import LisaHTTP

/// A retrieved page. The text is what the server gave an anonymous reader, converted to plain text with scripts,
/// styles and embedded content removed and links never followed; a paywalled or sign-in page yields only its public
/// part, so callers must not present it as the full article unless that is what was served (NEWS-01).
public struct RetrievedPage: Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let captureID: CaptureID
    /// The captured address, as requested.
    public let requestedURL: URL
    /// The address that produced the page, after any redirects.
    public let finalURL: URL
    /// The page's title, when it has one.
    public let title: String?
    /// The visible text, bounded by ``OwnerPageOptions/maxTextCharacters``.
    public let text: String
    /// Whether the text was cut at the bound.
    public let textTruncated: Bool
    /// `text/html`, `application/xhtml+xml` or `text/plain`.
    public let mediaType: String
    /// The character set the page was decoded with.
    public let characterSet: String
    /// How many active or embedded elements (scripts, frames, images …) were removed.
    public let removedElements: Int
    /// The page exactly as received, for raw-content retention.
    public let rawContent: Data
    public let retrievedAt: Date

    public var description: String {
        "page for capture \(captureID) from \(URLPolicy.origin(of: finalURL)), \(text.count) characters"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["page": description]) }
}
