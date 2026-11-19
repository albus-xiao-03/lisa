// Typed, stable identifiers for every persisted entity kind.

import Foundation

/// Marks the entity kind an identifier belongs to.
public protocol EntityTag: Sendable {}

/// A stable identifier whose type records its entity kind, so identifiers of different kinds cannot be mixed up.
public struct EntityID<Tag: EntityTag>: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A new random identifier.
    public static func random() -> EntityID {
        EntityID(UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }

    public static func < (lhs: EntityID, rhs: EntityID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

extension EntityID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty, value.utf8.count <= 256 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid identifier")
        }
        rawValue = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum SourceTag: EntityTag {}
public enum EvidenceTag: EntityTag {}
public enum EmailTag: EntityTag {}
public enum OccurrenceTag: EntityTag {}
public enum TaskTag: EntityTag {}
public enum ProposalTag: EntityTag {}
public enum IdeaTag: EntityTag {}
public enum CaptureTag: EntityTag {}
public enum PreferenceTag: EntityTag {}
public enum NewsTag: EntityTag {}
public enum PlanTag: EntityTag {}
public enum BriefTag: EntityTag {}
public enum ReminderTag: EntityTag {}
public enum DeliveryTag: EntityTag {}
public enum AuditTag: EntityTag {}
public enum DeviceTag: EntityTag {}
public enum NotificationTag: EntityTag {}

public typealias SourceID = EntityID<SourceTag>
public typealias EvidenceID = EntityID<EvidenceTag>
public typealias EmailID = EntityID<EmailTag>
public typealias OccurrenceID = EntityID<OccurrenceTag>
public typealias TaskID = EntityID<TaskTag>
public typealias ProposalID = EntityID<ProposalTag>
public typealias IdeaID = EntityID<IdeaTag>
public typealias CaptureID = EntityID<CaptureTag>
public typealias PreferenceID = EntityID<PreferenceTag>
public typealias NewsID = EntityID<NewsTag>
public typealias PlanID = EntityID<PlanTag>
public typealias BriefID = EntityID<BriefTag>
public typealias ReminderID = EntityID<ReminderTag>
public typealias DeliveryID = EntityID<DeliveryTag>
public typealias AuditID = EntityID<AuditTag>
public typealias DeviceID = EntityID<DeviceTag>
public typealias NotificationID = EntityID<NotificationTag>
