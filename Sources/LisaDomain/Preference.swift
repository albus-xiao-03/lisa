// Owner preferences: explicit or inferred values with evidence, confirmation and consequential-setting protection.

import Foundation

/// Whether the owner stated a preference or Lisa inferred it.
public enum PreferenceOrigin: String, Codable, Sendable {
    case explicit
    case inferred
}

/// A preference value.
public enum PreferenceValue: Hashable, Codable, Sendable, CustomStringConvertible {
    case text(String)
    case number(Double)
    case flag(Bool)
    case list([String])

    public var description: String {
        switch self {
        case .text(let value): value
        case .number(let value): String(value)
        case .flag(let value): value ? "true" : "false"
        case .list(let values): values.joined(separator: ", ")
        }
    }
}

/// A preference key. Known keys are listed as static members; consequential keys are protected.
public struct PreferenceKey: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static func < (lhs: PreferenceKey, rhs: PreferenceKey) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let timeZone = PreferenceKey("timeZone")
    public static let planningWindows = PreferenceKey("planning.windows")
    public static let protectedTime = PreferenceKey("planning.protectedTime")
    public static let bufferMinutes = PreferenceKey("planning.bufferMinutes")
    public static let maximumAllocation = PreferenceKey("planning.maximumAllocation")
    public static let briefTime = PreferenceKey("brief.time")
    public static let briefLength = PreferenceKey("brief.targetWords")
    public static let briefTopics = PreferenceKey("brief.topics")
    public static let newsInterests = PreferenceKey("news.interests")
    public static let mutedSources = PreferenceKey("news.mutedSources")
    public static let mutedTopics = PreferenceKey("news.mutedTopics")
    public static let reminderOffsets = PreferenceKey("reminders.deadlineOffsetsMinutes")
    public static let reminderChannels = PreferenceKey("reminders.channels")
    public static let quietHours = PreferenceKey("quietHours")
    public static let callEscalation = PreferenceKey("calls.escalation")
    public static let ideaExplorationMinutes = PreferenceKey("ideas.explorationMinutes")
    public static let ideaExplorationFrequency = PreferenceKey("ideas.explorationPerWeek")
    public static let modelEndpoint = PreferenceKey("model.endpoint")
    public static let modelDataSharing = PreferenceKey("model.dataSharing")
    public static let approvedEmailAddresses = PreferenceKey("delivery.approvedEmailAddresses")
    public static let approvedPhoneNumber = PreferenceKey("delivery.approvedPhoneNumber")
    public static let emailEnabled = PreferenceKey("delivery.emailEnabled")
    public static let callsEnabled = PreferenceKey("delivery.callsEnabled")
    public static let timeSensitiveNotifications = PreferenceKey("notifications.timeSensitive")

    /// Keys that change who is contacted, how, or where private content goes. Inference and paired devices may never
    /// change them.
    public static let consequential: Set<PreferenceKey> = [
        .callEscalation, .modelEndpoint, .modelDataSharing, .approvedEmailAddresses, .approvedPhoneNumber,
        .emailEnabled, .callsEnabled, .timeSensitiveNotifications,
    ]

    /// Whether this key is consequential.
    public var isConsequential: Bool { PreferenceKey.consequential.contains(self) }
}

/// A stored preference.
public struct Preference: Entity {
    public static let collectionName = "preferences"
    public let id: PreferenceID
    public var revision: Revision
    public var updatedAt: Date
    public var key: PreferenceKey
    public var value: PreferenceValue
    public var origin: PreferenceOrigin
    public var evidenceIDs: [EvidenceID]
    /// Inferred preferences start unconfirmed and do not take effect until the owner confirms them.
    public var confirmed: Bool

    public init(
        id: PreferenceID = .random(), key: PreferenceKey, value: PreferenceValue, origin: PreferenceOrigin,
        evidenceIDs: [EvidenceID] = [], now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.key = key
        self.value = value
        self.origin = origin
        self.evidenceIDs = evidenceIDs
        self.confirmed = origin == .explicit
    }

    /// Whether the preference currently takes effect.
    public var isEffective: Bool { origin == .explicit || confirmed }
}
