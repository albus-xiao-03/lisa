// Discord error bodies read leniently: the JSON error code, and the retry_after and global members of a 429 body.

import Foundation

/// What a Discord error body says, reduced to values Lisa can act on. The free-text `message` is never kept.
///
/// Errors carry a numeric `code` and a `message` (https://docs.discord.com/developers/topics/opcodes-and-status-codes.md#json);
/// a 429 body is `{"message", "retry_after" (float seconds), "global" (boolean), "code"?}`
/// (https://docs.discord.com/developers/topics/rate-limits.md#exceeding-a-rate-limit).
struct DiscordErrorBody: Hashable, Sendable, Decodable {
    var code: Int?
    var retryAfter: Double?
    var global: Bool?

    private enum CodingKeys: String, CodingKey {
        case code
        case retryAfter = "retry_after"
        case global
    }

    init(code: Int? = nil, retryAfter: Double? = nil, global: Bool? = nil) {
        self.code = code
        self.retryAfter = retryAfter
        self.global = global
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.lenient(Int.self, forKey: .code)
        retryAfter = container.lenient(Double.self, forKey: .retryAfter).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        global = container.lenient(Bool.self, forKey: .global)
    }

    /// Reads a body; an unreadable one yields no details.
    static func parse(_ body: Data) -> DiscordErrorBody {
        (try? JSONDecoder().decode(DiscordErrorBody.self, from: body)) ?? DiscordErrorBody()
    }
}
