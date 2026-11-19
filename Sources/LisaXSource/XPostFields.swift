// The post fields and expansions Lisa requests from X: the one place that names X's fields parameter.

/// What Lisa asks X to include with each post.
///
/// The name of X's post-fields query parameter is unresolved in X's own documentation (read on 2026-11-16):
/// - The X API v2 OpenAPI specification, version 2.174 (https://docs.x.com/openapi.json, rendered at
///   https://docs.x.com/x-api/users/get-posts.md), defines `PostFieldsParameter` as `post.fields` for
///   `GET /2/users/{id}/tweets` and 39 other operations.
/// - The Fields guide (https://docs.x.com/x-api/fundamentals/fields.md) maps "Post (Tweet)" to `tweet.fields`, and the
///   changelog (https://docs.x.com/changelog.md) tells readers on Jun 3, 2026 to "request `tweet.fields=paid_partnership`"
///   and announces no rename.
/// - The same 2.174 specification still defines `tweet.fields` inline for its ten streaming operations, and its
///   `post.fields` enumeration leaves out fields its post schema keeps (`author_id`, `referenced_posts`), which points to
///   an unannounced mechanical rename in the generated specification rather than a documented API change.
///
/// Lisa therefore sends `tweet.fields`, with that vocabulary's value names. Only a live request can confirm the choice
/// (NOT_RUN_CREDENTIALS). Responses are read under both vocabularies (`note_tweet` and `note_post`), so a rename
/// affects only this type.
enum XPostFields {
    /// The query parameter that selects post fields.
    static let parameterName = "tweet.fields"
    /// `created_at` dates each post, `note_tweet` carries the full text of posts longer than 280 characters, and
    /// `withheld` reports content withheld in some countries.
    static let values = ["created_at", "note_tweet", "withheld"]
    /// The query parameter that selects expansions; its name is the same in both vocabularies.
    static let expansionsParameterName = "expansions"
    /// Includes the author's user object, whose `username` forms each post's link (Fields guide, "Fields for related
    /// objects").
    static let expansions = ["author_id"]
}
