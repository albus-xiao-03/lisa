// Reading a list the host returns in pages, up to a bound, for screens that show every item at once or look for one.

import Foundation
import LisaAPIContract
import LisaClient

/// Reads the pages of a list from the host, passing each page's `nextCursor` to the next request, up to a bound. Used
/// where a screen shows every item at once (the inbox) or needs one item the API has no route to read alone (an idea or
/// an event proposal after a conflict). It runs on the main actor, as the models and `ReadRunner` do.
@MainActor
enum PageCollector {
    /// The items read, and whether the host had no more pages when reading stopped.
    struct Collected<Item: Sendable>: Sendable {
        /// The items, in the host's order.
        var items: [Item]
        /// Whether every page was read; `false` when the bound stopped the reading first.
        var isComplete: Bool
    }

    /// The most pages read for one list.
    static let defaultPageLimit = 5

    /// Reads pages through `page` until the host has no more or `maxPages` pages were read.
    static func collect<Item: Codable & Hashable & Sendable>(
        maxPages: Int = defaultPageLimit, _ page: (_ cursor: String?) async throws(ClientError) -> Page<Item>
    ) async throws(ClientError) -> Collected<Item> {
        var items: [Item] = []
        var cursor: String?
        for _ in 0..<max(1, maxPages) {
            let next = try await page(cursor)
            items += next.items
            guard let following = next.nextCursor else { return Collected(items: items, isComplete: true) }
            cursor = following
        }
        return Collected(items: items, isComplete: false)
    }

    /// The first item whose `key` is `value`, reading pages through `page` until it is found, the host has no more, or
    /// `maxPages` pages were read; `nil` when it was not found.
    static func first<Item: Codable & Hashable & Sendable>(
        maxPages: Int = defaultPageLimit, whose key: KeyPath<Item, String>, is value: String,
        _ page: (_ cursor: String?) async throws(ClientError) -> Page<Item>
    ) async throws(ClientError) -> Item? {
        var cursor: String?
        for _ in 0..<max(1, maxPages) {
            let next = try await page(cursor)
            if let found = next.items.first(where: { $0[keyPath: key] == value }) { return found }
            guard let following = next.nextCursor else { return nil }
            cursor = following
        }
        return nil
    }
}
