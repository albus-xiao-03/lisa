// The versioned X timeline cursor: a since_id high-water mark plus an optional window of older pages still to read.

import Foundation
import LisaPorts

/// Where synchronization of one account's posts stands.
///
/// X returns posts newest first, and `since_id` limits a request to posts newer than the high-water mark. When more
/// than one page of new posts exists, the newest page arrives first and the older ones follow through
/// `pagination_token` (https://docs.x.com/x-api/fundamentals/pagination.md). The high-water mark therefore moves only
/// when such a window of pages is complete; until then the window remembers the newest identifier seen and the token
/// of the next page, so each page can be stored before the next one is read and nothing is skipped.
///
/// The cursor is persisted as compact JSON with a version number: `{"v":1,"since":"…","high":"…","next":"…"}`.
struct XTimelinePosition: Hashable, Sendable {
    /// An incomplete window of pages newer than `since`.
    struct Window: Hashable, Sendable {
        /// The newest post identifier seen in this window; it becomes the high-water mark when the window completes.
        var high: String
        /// The token of the next, older page; nil restarts the window from the newest page.
        var next: String?
    }

    /// Every post with this identifier or an older one has been processed (or predates the first synchronization).
    var since: String?
    var window: Window?

    /// The longest cursor accepted from storage.
    static let maxEncodedLength = 2_048
    /// The longest pagination token accepted.
    static let maxTokenLength = 512

    init(since: String? = nil, window: Window? = nil) {
        self.since = since
        self.window = window
    }

    /// Reads a stored cursor; nil means the account has never been read.
    init(cursor: String?) throws(ConnectorError) {
        guard let cursor else {
            self.init()
            return
        }
        let unreadable = ConnectorError(
            .internalError, "the stored X synchronization position is not one this version of Lisa can read")
        guard cursor.utf8.count <= Self.maxEncodedLength,
            let stored = try? JSONDecoder().decode(Stored.self, from: Data(cursor.utf8)), stored.v == 1
        else { throw unreadable }
        if let since = stored.since, !XIdentifier.isValid(since) { throw unreadable }
        if let high = stored.high {
            guard stored.since != nil, XIdentifier.isValid(high) else { throw unreadable }
            if let next = stored.next, !Self.isValidToken(next) { throw unreadable }
            self.init(since: stored.since, window: Window(high: high, next: stored.next))
        } else {
            guard stored.next == nil else { throw unreadable }
            self.init(since: stored.since)
        }
    }

    /// The cursor to persist.
    var encoded: String {
        let stored = Stored(v: 1, since: since, high: window?.high, next: window?.next)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stored) else { return #"{"v":1}"# }
        return String(decoding: data, as: UTF8.self)
    }

    /// True before anything has been read: the first synchronization reads only the newest page.
    var isInitial: Bool { since == nil && window == nil }

    /// The position after a page with the posts `ids` and, when more pages follow, `nextToken`.
    ///
    /// - The first synchronization reads only the newest page and starts following from its newest post; older history
    ///   is not imported.
    /// - Otherwise a `nextToken` opens or continues a window, and the window's end moves the high-water mark to the
    ///   newest post seen in it.
    func advanced(pageIDs ids: [String], nextToken: String?) -> (position: XTimelinePosition, hasMore: Bool) {
        let pageNewest = XIdentifier.largest(ids)
        if isInitial {
            return (XTimelinePosition(since: pageNewest), false)
        }
        let windowHigh = XIdentifier.largest([window?.high, pageNewest]) ?? since
        if let nextToken, let windowHigh {
            return (XTimelinePosition(since: since, window: Window(high: windowHigh, next: nextToken)), true)
        }
        return (XTimelinePosition(since: XIdentifier.largest([since, windowHigh])), false)
    }

    /// The same window read again from its newest page, after X refused its pagination token (tokens "may expire after
    /// some time"). Posts already stored are recognized by their identifiers, so reading them again duplicates nothing.
    func restartingWindow() -> XTimelinePosition {
        XTimelinePosition(since: since, window: window.map { Window(high: $0.high, next: nil) })
    }

    /// Opaque tokens are kept only when they are short and made of URL-safe characters, so they can be stored and sent
    /// back unchanged.
    static func isValidToken(_ token: String) -> Bool {
        (1...maxTokenLength).contains(token.utf8.count)
            && token.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x5F || byte == 0x2E || byte == 0x7E || byte == 0x3D
            }
    }

    private struct Stored: Codable {
        var v: Int
        var since: String?
        var high: String?
        var next: String?
    }
}
