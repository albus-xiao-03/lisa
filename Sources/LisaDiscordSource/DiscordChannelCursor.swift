// The versioned Discord channel cursor: an after-snowflake high-water mark plus an optional window read backwards.

import Foundation
import LisaPorts

/// Which page of channel messages to request.
enum DiscordPageQuery: Hashable, Sendable {
    /// The newest messages (no `around`, `before` or `after`).
    case newest
    /// Messages after this snowflake.
    case after(String)
    /// Messages before this snowflake.
    case before(String)
}

/// Where synchronization of one channel stands.
///
/// Discord returns each page "from newest to oldest" and documents `after` only as "Get messages after this message
/// ID" with a `limit` of 1 to 100 (https://docs.discord.com/developers/resources/message.md#get-channel-messages). A page
/// shorter than the limit is therefore everything after the mark, whichever messages Discord chooses for a full page.
/// A full page may leave a gap below its oldest message, so the connector then reads backwards with `before` until it
/// meets the mark, and only then moves the mark to the newest message of that window. The mark never passes a message
/// that was not read, under either reading of how Discord fills a full `after` page.
///
/// The cursor is persisted as compact JSON with a version number: `{"v":1,"after":"…","high":"…","before":"…"}`.
struct DiscordChannelPosition: Hashable, Sendable {
    /// Messages newer than `after` whose gap down to `after` is still being read.
    struct Window: Hashable, Sendable {
        /// The newest message seen in this window; it becomes the mark when the window closes.
        var high: String
        /// The next page holds messages before this one.
        var before: String
    }

    /// Every message with this snowflake or an older one has been processed (or predates the first synchronization).
    var after: String?
    var window: Window?

    /// The longest cursor accepted from storage.
    static let maxEncodedLength = 1_024

    init(after: String? = nil, window: Window? = nil) {
        self.after = after
        self.window = window
    }

    /// Reads a stored cursor; nil means the channel has never been read.
    init(cursor: String?) throws(ConnectorError) {
        guard let cursor else {
            self.init()
            return
        }
        let unreadable = ConnectorError(
            .internalError, "the stored Discord synchronization position is not one this version of Lisa can read")
        guard cursor.utf8.count <= Self.maxEncodedLength,
            let stored = try? JSONDecoder().decode(Stored.self, from: Data(cursor.utf8)), stored.v == 1
        else { throw unreadable }
        if let after = stored.after, !DiscordSnowflake.isValid(after) { throw unreadable }
        switch (stored.high, stored.before) {
        case (nil, nil):
            self.init(after: stored.after)
        case (let high?, let before?):
            guard let after = stored.after, let highValue = DiscordSnowflake.value(high),
                let beforeValue = DiscordSnowflake.value(before), let afterValue = DiscordSnowflake.value(after),
                afterValue < beforeValue, beforeValue <= highValue
            else { throw unreadable }
            self.init(after: after, window: Window(high: high, before: before))
        default:
            throw unreadable
        }
    }

    /// The cursor to persist.
    var encoded: String {
        let stored = Stored(v: 1, after: after, high: window?.high, before: window?.before)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(stored) else { return #"{"v":1}"# }
        return String(decoding: data, as: UTF8.self)
    }

    /// True before anything has been read: the first synchronization reads only the newest page.
    var isInitial: Bool { after == nil && window == nil }

    /// The page to request next.
    var query: DiscordPageQuery {
        if let window { return .before(window.before) }
        if let after { return .after(after) }
        return .newest
    }

    /// Whether a message from the requested page is new: after the mark and, inside a window, before its edge.
    func isNew(_ id: UInt64) -> Bool {
        if let after, let mark = DiscordSnowflake.value(after), id <= mark { return false }
        if let window, let edge = DiscordSnowflake.value(window.before), id >= edge { return false }
        return true
    }

    /// The position after a page with the messages `ids`, requested with `pageSize`.
    ///
    /// - The first synchronization takes the newest page and starts following from its newest message.
    /// - After the mark, a short page completes the pass; a full page of new messages opens a window below it.
    /// - Inside a window, a full page of new messages moves the window's edge down; anything else (an old message, or
    ///   a short page) closes it, moves the mark to the window's newest message, and asks for one more pass, because
    ///   newer messages may follow the window.
    func advanced(pageIDs ids: [UInt64], pageSize: Int) throws(ConnectorError) -> (
        position: DiscordChannelPosition, hasMore: Bool
    ) {
        let fresh = ids.filter(isNew)
        let newest = fresh.max().map(String.init)
        let full = ids.count >= pageSize && fresh.count == ids.count
        guard let after else {
            return (DiscordChannelPosition(after: newest), false)
        }
        guard let window else {
            guard full, let newest, let oldest = fresh.min() else {
                return (DiscordChannelPosition(after: Self.larger(after, newest)), false)
            }
            return (DiscordChannelPosition(after: after, window: Window(high: newest, before: String(oldest))), true)
        }
        if let edge = DiscordSnowflake.value(window.before), ids.contains(where: { $0 >= edge }) {
            throw ConnectorError(.parse, "Discord returned messages outside the requested range")
        }
        if full, let oldest = fresh.min() {
            let high = Self.larger(window.high, newest) ?? window.high
            return (DiscordChannelPosition(after: after, window: Window(high: high, before: String(oldest))), true)
        }
        return (DiscordChannelPosition(after: Self.larger(after, window.high)), true)
    }

    private static func larger(_ first: String?, _ second: String?) -> String? {
        switch (first.flatMap(DiscordSnowflake.value), second.flatMap(DiscordSnowflake.value)) {
        case (let a?, let b?): String(max(a, b))
        case (let a?, nil): String(a)
        case (nil, let b?): String(b)
        case (nil, nil): nil
        }
    }

    private struct Stored: Codable {
        var v: Int
        var after: String?
        var high: String?
        var before: String?
    }
}
