// Decodes one page of an account's posts: the posts, the author's username, the next-page token and partial errors.

import Foundation
import LisaPorts

/// One post, with only the members Lisa uses.
struct XPost: Hashable, Sendable {
    var id: String
    var text: String
    /// `created_at`, an RFC 3339 timestamp.
    var createdAt: String?
    /// The full text of a post longer than 280 characters: `note_tweet` (Fields guide vocabulary) or `note_post`
    /// (specification 2.174), whichever is present.
    var noteText: String?
    /// Whether X marks the post as withheld in some countries.
    var isWithheld: Bool

    /// The text to store: the full note text when X sent one, otherwise `text`.
    var fullText: String {
        if let noteText, !noteText.isEmpty { return noteText }
        return text
    }
}

extension XPost: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt = "created_at"
        case noteTweet = "note_tweet"
        case notePost = "note_post"
        case withheld
    }

    private struct Note: Decodable {
        var text: String?
    }

    /// `id` and `text` are required (X returns them by default); optional members of an unexpected type are ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        let tweetNote = try? container.decodeIfPresent(Note.self, forKey: .noteTweet)
        let postNote = try? container.decodeIfPresent(Note.self, forKey: .notePost)
        noteText = (tweetNote ?? postNote)?.text
        isWithheld = container.contains(.withheld) && !((try? container.decodeNil(forKey: .withheld)) ?? true)
    }
}

/// A user object from `includes.users`.
struct XUser: Hashable, Sendable {
    var id: String?
    var username: String?
}

extension XUser: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case username
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        username = try? container.decodeIfPresent(String.self, forKey: .username)
    }
}

/// One page of `GET /2/users/{id}/tweets` (`GetUsersPostsResponse`: `data`, `errors`, `includes`, `meta`). Unknown
/// members are ignored.
struct XTimelinePage: Hashable, Sendable {
    var posts: [XPost]
    var users: [XUser]
    /// `meta.next_token`: present while older pages remain.
    var nextToken: String?
    /// Problems reported alongside (or instead of) the posts.
    var problems: XProblemDetails
    /// How many entries the `errors` member holds, including any whose details could not be read.
    var errorCount: Int
    /// Whether the response carried a `data` member.
    var hasData: Bool
}

extension XTimelinePage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case data
        case includes
        case meta
        case errors
    }

    private struct Includes: Decodable {
        var users: [XUser]?
    }

    private struct Meta: Decodable {
        var nextToken: String?

        private enum CodingKeys: String, CodingKey {
            case nextToken = "next_token"
        }
    }

    /// Posts and the pagination token are read strictly, because storing them and continuing correctly depends on them;
    /// included users and partial errors are read leniently.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasData = container.contains(.data)
        posts = try container.decodeIfPresent([XPost].self, forKey: .data) ?? []
        nextToken = try container.decodeIfPresent(Meta.self, forKey: .meta)?.nextToken
        users = ((try? container.decodeIfPresent(Includes.self, forKey: .includes))?.users) ?? []
        let entries = (try? container.decodeIfPresent([XProblemEntry].self, forKey: .errors)) ?? []
        problems = XProblemDetails(entries: entries)
        let errorList = try? container.nestedUnkeyedContainer(forKey: .errors)
        errorCount = max(entries.count, errorList?.count ?? 0)
    }
}

/// Decodes and checks a successful page.
enum XTimelineDecoder {
    static func decode(_ body: Data, pageSize: Int) throws(ConnectorError) -> XTimelinePage {
        let page: XTimelinePage
        do {
            page = try JSONDecoder().decode(XTimelinePage.self, from: body)
        } catch {
            throw ConnectorError(.parse, "the X response was not the expected JSON")
        }
        guard page.posts.count <= pageSize else {
            throw ConnectorError(.parse, "X returned more posts than were requested")
        }
        guard page.posts.allSatisfy({ XIdentifier.isValid($0.id) }) else {
            throw ConnectorError(.parse, "X returned a post without a valid identifier")
        }
        if let token = page.nextToken, !XTimelinePosition.isValidToken(token) {
            throw ConnectorError(.parse, "X returned a pagination token that Lisa cannot store safely")
        }
        return page
    }
}
