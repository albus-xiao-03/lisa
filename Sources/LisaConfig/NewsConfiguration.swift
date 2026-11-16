// The `news` section: explicit news interests and the sources and topics the owner muted.

/// News preferences (NEWS-01, MEM-01). Items need an interest match to be selected; muted ones never are.
public struct NewsConfiguration: Hashable, Sendable {
    /// Explicit interests that make an item relevant, such as "local transit".
    public let interests: [String]
    /// Names of sources whose items are left out.
    public let mutedSources: [String]
    /// Topics whose items are left out.
    public let mutedTopics: [String]

    /// No interests and nothing muted.
    public static let defaultValue = NewsConfiguration(interests: [], mutedSources: [], mutedTopics: [])

    static func decode(_ section: ConfigSection?) -> NewsConfiguration {
        let defaults = defaultValue
        guard let section else { return defaults }
        defer { section.finish() }
        return NewsConfiguration(
            interests: section.textList("interests", default: defaults.interests, maxCount: 100),
            mutedSources: section.textList("mutedSources", default: defaults.mutedSources, maxCount: 100),
            mutedTopics: section.textList("mutedTopics", default: defaults.mutedTopics, maxCount: 100))
    }
}
