// What a request to read a captured link's page did, and why such a request was refused (NEWS-01).

import Foundation
import LisaDomain
import LisaPorts

/// What one request to read a captured link's page did.
public struct CapturedPageOutcome: Sendable {
    public var capture: Capture
    /// The capture's news item: updated when the page was read, otherwise exactly as it was.
    public var item: NewsItem
    /// Why the page could not be read, when it could not. Nothing from the page was kept then.
    public var failure: ConnectorError?
    /// How many characters of the page's text the item keeps; 0 when none was read.
    public var keptCharacters: Int
    /// Whether the page's text was cut, at the retriever's bound or at the item's.
    public var textTruncated: Bool

    public init(
        capture: Capture, item: NewsItem, failure: ConnectorError?, keptCharacters: Int, textTruncated: Bool
    ) {
        self.capture = capture
        self.item = item
        self.failure = failure
        self.keptCharacters = keptCharacters
        self.textTruncated = textTruncated
    }

    /// Whether the page was read and kept.
    public var retrieved: Bool { failure == nil }
}

/// Why a request to read a captured link's page was refused or did not finish. A page that cannot be read for a lasting
/// reason, such as a sign-in page, is an outcome (`CapturedPageOutcome.failure`), not one of these errors.
public enum CapturedPageError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The capture's link is never read: an idea, text or an Apple News share, or a capture the owner did not make.
    case notRetrievable(String)
    /// The capture has no news item any more, because the owner deleted it.
    case itemMissing
    /// The page was already read for this news item; a captured link is read once.
    case alreadyRetrieved
    /// The same page is being read for another request.
    case inProgress
    /// The page could not be read for a reason that can pass, such as a timeout or an unreachable site; nothing was
    /// kept, and the request can be retried after `retryAfterSeconds`.
    case temporarilyUnavailable(ConnectorError, retryAfterSeconds: Int)
    /// This host cannot read captured links.
    case unavailable(String)

    public var description: String {
        switch self {
        case .notRetrievable(let reason): reason
        case .itemMissing: "the news item of this capture was deleted, so there is nothing to read the page into"
        case .alreadyRetrieved: "the page behind this link was already read; a captured link is read once"
        case .inProgress: "the page behind this link is being read for another request"
        case .temporarilyUnavailable(let error, _): "the page could not be read now: \(error.summary)"
        case .unavailable(let reason): reason
        }
    }
}
