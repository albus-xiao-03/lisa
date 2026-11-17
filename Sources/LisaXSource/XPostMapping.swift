// Turns a page of X posts into fetched items in the news-ingestion contract, with notes about missing details.

import Foundation
import LisaPorts
import LisaTime

/// Maps posts to `FetchedItem`s of kind `.post`, as news ingestion reads them: the item data is the post's text as
/// UTF-8, `metadata["url"]` is the post's link, `metadata["title"]` (optional) overrides the first line as the title,
/// `receivedAt` is the publication time, and `externalID` (`x:<post id>`) is the stable key.
enum XPostMapping {
    /// The capability notes this mapping can add. They contain no counts, so repeated synchronizations do not pile up
    /// variants of the same note.
    enum Note {
        static let undated = "X did not say when some posts were created; they are dated by when Lisa read them"
        static let unlinked = "X did not return the account's username, so some posts are stored without a link"
        static let withheld = "X marks some posts from this account as withheld in some countries"
    }

    struct Result: Sendable {
        var items: [FetchedItem]
        var notes: [String]
    }

    /// The title used when a post has no text, so it is not stored as an empty item.
    static let untitled = "Post without text (media or a link only)"

    /// Items for `posts`, oldest first. Posts not newer than `since` (which `since_id` already excludes) are dropped.
    static func items(for page: XTimelinePage, userID: String, after since: String?, fetchedAt: Date) -> Result {
        let username = page.users.first { $0.id == userID }?.username.flatMap { isUsername($0) ? $0 : nil }
        var items: [FetchedItem] = []
        var notes: Set<String> = []
        let posts = page.posts.sorted { (XIdentifier.value($0.id) ?? 0) < (XIdentifier.value($1.id) ?? 0) }
        for post in posts {
            if let since, !XIdentifier.isGreater(post.id, than: since) { continue }
            let text = XPostText.normalized(post.fullText)
            var metadata: [String: String] = [:]
            if let username {
                metadata["url"] = "https://x.com/\(username)/status/\(post.id)"
            } else {
                notes.insert(Note.unlinked)
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { metadata["title"] = untitled }
            let created = post.createdAt.flatMap(InternetDateParser.parseISO8601)
            if created == nil { notes.insert(Note.undated) }
            if post.isWithheld { notes.insert(Note.withheld) }
            items.append(
                FetchedItem(
                    externalID: "x:\(post.id)", kind: .post, data: Data(text.utf8), receivedAt: created ?? fetchedAt,
                    metadata: metadata))
        }
        return Result(items: items, notes: notes.sorted())
    }

    /// A handle made of ASCII letters, digits and underscores (at most 50), which is safe to place in a link.
    static func isUsername(_ text: String) -> Bool {
        (1...50).contains(text.utf8.count)
            && text.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                    || byte == 0x5F
            }
    }
}
