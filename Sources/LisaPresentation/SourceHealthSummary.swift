// One source as the settings screen shows it: on or off, how fresh its data is, and why it fails.

import Foundation
import LisaAPIContract

/// One source from health (UI-01: sources) in plain words: whether it is on, how fresh its data is, and why it fails.
/// The host reports no addresses or credentials of a source. The failure class is a diagnostic.
public struct SourceHealthSummary: Hashable, Sendable, Identifiable {
    /// The source's identifier.
    public var id: String
    /// The source's name.
    public var name: String
    /// The host's kind, such as `mailbox`.
    public var kind: String
    /// The kind in words, such as "Mailbox".
    public var kindLabel: String
    /// Whether the source is on.
    public var enabled: Bool
    /// The host's freshness: `fresh`, `stale`, `neverSynchronized` or `disabled`.
    public var freshness: String
    /// The freshness in words, such as "Up to date".
    public var freshnessLabel: String
    /// Whether the latest synchronization failed.
    public var isFailing: Bool
    /// Why it fails, without private content.
    public var problem: String?
    /// Diagnostics: the failure's class, such as `authentication`.
    public var failureClass: String?
    /// When data was last read successfully.
    public var lastSuccessAt: Date?
    /// When reading was last tried.
    public var lastAttemptAt: Date?
    /// When the host tries again after a failure, if it said.
    public var retryAfter: Date?
    /// What the source cannot do, such as a capability its account lacks.
    public var notes: [String]

    /// The summary of `source`.
    public init(_ source: SourceStatusDTO) {
        id = source.id
        name = source.name
        kind = source.kind
        kindLabel = Self.kindLabel(source.kind)
        enabled = source.enabled
        freshness = source.freshness
        freshnessLabel = Self.freshnessLabel(source.freshness)
        isFailing = source.failing
        problem = source.failureSummary
        failureClass = source.failureClass
        lastSuccessAt = source.lastSuccessAt
        lastAttemptAt = source.lastAttemptAt
        retryAfter = source.retryAfter
        notes = source.notes
    }

    /// Whether the source is on and failing or out of date, as health counts it.
    public var needsAttention: Bool { enabled && (isFailing || freshness == "stale") }

    /// The source in one phrase for assistive technologies.
    public var accessibilityLabel: String {
        var label = "\(name), \(kindLabel), \(freshnessLabel)"
        if isFailing { label += ", failing" + (problem.map { ": \($0)" } ?? "") }
        return label
    }

    /// When data was last read, in words such as "Last read 2 hours ago", or that it was never read.
    public func lastReadPhrase(at now: Date) -> String {
        guard let lastSuccessAt else { return "Never read." }
        return "Last read \(AgePhrase.english(now.timeIntervalSince(lastSuccessAt))) ago."
    }

    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "mailbox": "Mailbox"
        case "calendarFeed": "Calendar"
        case "newsFeed": "News feed"
        case "xAccount": "X account"
        case "discordChannel": "Discord channel"
        case "manualCapture": "Captures"
        case "localImport": "Local files"
        default: kind
        }
    }

    private static func freshnessLabel(_ freshness: String) -> String {
        switch freshness {
        case "fresh": "Up to date"
        case "stale": "Out of date"
        case "neverSynchronized": "Not read yet"
        case "disabled": "Turned off"
        default: freshness
        }
    }
}
