// A morning brief: readable and spoken text built from grounded items, with versions and generation state.

import Foundation
import LisaTime

/// Brief sections, in reading order (BRIEF-01).
public enum BriefSection: String, Codable, Sendable, CaseIterable {
    case commitments
    case deadlines
    case email
    case events
    case ideas
    case news
    case changes
    case sourceHealth
}

/// A link from a brief item to its supporting record or original source.
public struct SourceReference: Hashable, Codable, Sendable {
    public var recordKind: String
    public var recordID: String
    public var originalURL: String?

    public init(recordKind: String, recordID: String, originalURL: String? = nil) {
        self.recordKind = recordKind
        self.recordID = recordID
        self.originalURL = originalURL
    }
}

/// One grounded brief item. Both versions of the brief are rendered from the same items.
public struct BriefItem: Hashable, Codable, Sendable {
    public var section: BriefSection
    public var text: String
    public var spokenText: String
    public var references: [SourceReference]
    /// Material items (commitments, warnings, uncertainty) must appear in both versions.
    public var isMaterial: Bool
    public var uncertainty: String?
    /// Lower numbers are kept first when the brief is shortened.
    public var priority: Int

    public init(
        section: BriefSection, text: String, spokenText: String, references: [SourceReference], isMaterial: Bool,
        uncertainty: String? = nil, priority: Int
    ) {
        self.section = section
        self.text = text
        self.spokenText = spokenText
        self.references = references
        self.isMaterial = isMaterial
        self.uncertainty = uncertainty
        self.priority = priority
    }
}

/// Whether a brief is current.
public enum BriefGenerationState: String, Codable, Sendable {
    case current
    case stale
    case failed
}

/// The canonical brief for one local date and time zone, with explicit versions (BRIEF-03).
public struct Brief: Entity {
    public static let collectionName = "briefs"
    public let id: BriefID
    public var revision: Revision
    public var updatedAt: Date
    public var localDate: LocalDate
    public var zone: TimeZoneID
    public var version: Int
    public var text: String
    public var spokenText: String
    public var items: [BriefItem]
    /// Lower-priority items left out of the shortened brief but available in the full view.
    public var omitted: [BriefItem]
    public var state: BriefGenerationState
    public var generatedAt: Date
    public var estimatedSpokenSeconds: Int
    /// True when the brief was composed from the structured template without a model.
    public var templateOnly: Bool
    public var lastFailure: String?

    public init(
        id: BriefID = .random(), localDate: LocalDate, zone: TimeZoneID, version: Int, text: String,
        spokenText: String, items: [BriefItem], omitted: [BriefItem], generatedAt: Date, estimatedSpokenSeconds: Int,
        templateOnly: Bool
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = generatedAt
        self.localDate = localDate
        self.zone = zone
        self.version = version
        self.text = text
        self.spokenText = spokenText
        self.items = items
        self.omitted = omitted
        self.state = .current
        self.generatedAt = generatedAt
        self.estimatedSpokenSeconds = estimatedSpokenSeconds
        self.templateOnly = templateOnly
        self.lastFailure = nil
    }

    /// The natural key: one canonical brief per local date and time zone.
    public static func key(date: LocalDate, zone: TimeZoneID) -> String {
        "\(date.iso)|\(zone.identifier)"
    }
}
