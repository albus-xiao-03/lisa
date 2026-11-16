// The `sources` list: each source's kind, stable key, name, schedule, freshness and retention choice.

import LisaDomain
import LisaTime

/// One configured information source (INGEST-01). Its `key` is the identity stored with everything imported from it:
/// changing the key makes a new source.
public struct SourceConfiguration: Hashable, Sendable {
    /// The stable identity: 1 to 64 lowercase letters, digits, `.`, `_` or `-`, starting with a letter or digit.
    public let key: String
    /// The display name; defaults to the key.
    public let name: String
    /// Whether Lisa synchronizes the source on a schedule. Off by default, so a newly configured source can be checked
    /// before scheduled operation starts.
    public let enabled: Bool
    /// The minutes between scheduled synchronizations.
    public let syncIntervalMinutes: Int
    /// The source is reported stale when its last successful synchronization is older than this.
    public let staleAfterMinutes: Int
    /// Whether records imported from the source are kept when it is disabled or removed.
    public let retainImportedOnDisable: Bool
    /// The kind, with its kind-specific settings.
    public let settings: SourceKindSettings

    /// The domain kind recorded on the `Source`.
    public var kind: SourceKind { settings.kind }

    /// `staleAfterMinutes` in seconds, as `Source.staleAfterSeconds` stores it.
    public var staleAfterSeconds: Int { staleAfterMinutes * 60 }

    /// Keys Lisa uses for her own sources.
    static let reservedKeys: Set<String> = ["manual-capture"]

    /// The kinds a configuration entry may declare; manual captures need no entry.
    static let configurableKinds: [SourceKind] = [
        .mailbox, .calendarFeed, .newsFeed, .xAccount, .discordChannel, .localImport,
    ]

    /// The default minutes between synchronizations for each kind.
    static func defaultSyncIntervalMinutes(for kind: SourceKind) -> Int {
        switch kind {
        case .mailbox, .localImport: 15
        case .calendarFeed, .discordChannel: 30
        case .newsFeed, .xAccount: 60
        case .manualCapture: 60
        }
    }

    static func decodeList(_ entries: [ConfigValue]?, defaultZone: TimeZoneID) -> [SourceConfiguration] {
        guard let entries else { return [] }
        var sources: [SourceConfiguration] = []
        var firstIndexByKey: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            guard let section = entry.section(), let source = decode(section, defaultZone: defaultZone) else {
                continue
            }
            if let first = firstIndexByKey[source.key] {
                section.report(
                    "key", "is already the key of sources[\(first)]",
                    fix: "give each source its own key; the key is how Lisa recognizes the source over time")
                continue
            }
            firstIndexByKey[source.key] = index
            sources.append(source)
        }
        return sources
    }

    private static func decode(_ section: ConfigSection, defaultZone: TimeZoneID) -> SourceConfiguration? {
        defer { section.finish() }
        let kind = decodeKind(section)
        let key = section.requiredValidated(
            "key", maxLength: 64, fix: "a short stable identifier such as lisa-mailbox", sourceKey)
        let name = section.text("name", maxLength: 100)
        let enabled = section.bool("enabled", default: false)
        let syncInterval = section.integer(
            "syncIntervalMinutes", default: kind.map(defaultSyncIntervalMinutes) ?? 30, in: 5...1440)
        let staleAfter = section.integer("staleAfterMinutes", default: max(360, 2 * syncInterval), in: 5...43_200)
        let retain = section.bool("retainImportedOnDisable", default: true)
        guard let kind else {
            // Without a kind the other keys cannot be judged, so only the kind is reported.
            section.skipUnknownKeyCheck()
            return nil
        }
        section.subject = "a setting of a \(kind.rawValue) source"
        let settings = SourceKindSettings.decode(kind, section: section, defaultZone: defaultZone)
        if staleAfter < syncInterval {
            section.report(
                "staleAfterMinutes", "must be at least syncIntervalMinutes",
                fix: "otherwise the source would be reported stale between scheduled synchronizations")
        }
        guard let key, let settings else { return nil }
        return SourceConfiguration(
            key: key, name: name ?? key, enabled: enabled, syncIntervalMinutes: syncInterval,
            staleAfterMinutes: staleAfter, retainImportedOnDisable: retain, settings: settings)
    }

    private static func decodeKind(_ section: ConfigSection) -> SourceKind? {
        let names = configurableKinds.map(\.rawValue).joined(separator: ", ")
        guard let value = section.value("kind") else {
            section.reportMissing("kind", fix: "one of \(names)")
            return nil
        }
        if case .string(let text) = value.node.value, text == SourceKind.manualCapture.rawValue {
            value.report("is not a configurable kind; items the owner shares need no source entry")
            return nil
        }
        return value.choice(of: configurableKinds)
    }

    private static func sourceKey(_ text: String) -> Result<String, ValueRefusal> {
        let scalars = text.unicodeScalars
        let isLowerAlphanumeric = { (scalar: Unicode.Scalar) in
            (0x61...0x7A).contains(scalar.value) || (0x30...0x39).contains(scalar.value)
        }
        let valid =
            scalars.first.map(isLowerAlphanumeric) == true
            && scalars.allSatisfy { isLowerAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "-" }
        guard valid else {
            return .failure(
                ValueRefusal("must be lowercase letters, digits, '.', '_' or '-', starting with a letter or digit"))
        }
        guard !reservedKeys.contains(text) else {
            return .failure(ValueRefusal("is reserved for the items the owner shares with Lisa"))
        }
        return .success(text)
    }
}
