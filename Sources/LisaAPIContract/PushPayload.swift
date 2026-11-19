// The push-payload schema and notification category and action identifiers shared by the host and the apps.

import Foundation

/// Notification categories registered by the apps at launch (plan §6.5). Each matches the host's category names.
public enum NotificationCategoryID: String, Codable, Hashable, Sendable, CaseIterable {
    case reminder = "LISA_REMINDER"
    case overdue = "LISA_OVERDUE"
    case planBlock = "LISA_PLAN_BLOCK"
    case eventProposal = "LISA_EVENT_PROPOSAL"
    case commitmentChange = "LISA_COMMITMENT_CHANGE"
    case brief = "LISA_BRIEF"

    /// The actions offered for the category; opening the item is always the default action.
    public var actions: [NotificationActionID] {
        switch self {
        case .reminder, .overdue: [.acknowledge, .snooze, .complete]
        case .planBlock: [.acknowledge, .snooze]
        case .commitmentChange: [.acknowledge]
        case .eventProposal, .brief: []
        }
    }

    /// The category for a payload's `lisa.kind` (the host's category name, such as `reminder`).
    public init?(kind: String) {
        switch kind {
        case "reminder": self = .reminder
        case "overdue": self = .overdue
        case "planBlock": self = .planBlock
        case "eventProposal": self = .eventProposal
        case "commitmentChange": self = .commitmentChange
        case "brief": self = .brief
        default: return nil
        }
    }

    /// The localization key of the generic title.
    public var titleKey: String { "\(rawValue)_TITLE" }
    /// The localization key of the generic body.
    public var bodyKey: String { "\(rawValue)_BODY" }
    /// The localization key of the body format used when the device opted in to titles; `%@` is the item title.
    public var titledBodyKey: String { "\(rawValue)_BODY_TITLED" }
}

/// Notification action identifiers.
public enum NotificationActionID: String, Codable, Hashable, Sendable, CaseIterable {
    case acknowledge = "LISA_ACKNOWLEDGE"
    case snooze = "LISA_SNOOZE"
    /// Requires the device to be unlocked.
    case complete = "LISA_COMPLETE"

    public var reminderAction: ReminderActionKind {
        switch self {
        case .acknowledge: .acknowledge
        case .snooze: .snooze
        case .complete: .complete
        }
    }
}

/// The custom `lisa` object in every push payload: only opaque identifiers and a schema version.
public struct LisaPushData: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    /// The host's category name, such as `reminder`.
    public var kind: String
    public var notificationID: String
    public var subjectKind: String
    public var subjectID: String
    public var subjectRevision: Int64

    public init(kind: String, notificationID: String, subjectKind: String, subjectID: String, subjectRevision: Int64) {
        self.version = LisaPushData.currentVersion
        self.kind = kind
        self.notificationID = notificationID
        self.subjectKind = subjectKind
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case kind
        case notificationID = "notification"
        case subjectKind
        case subjectID = "subject"
        case subjectRevision = "revision"
    }
}

/// The `aps.alert` dictionary. Text comes from localization keys; an item title is passed only as a format argument
/// when the device opted in to titles.
public struct PushAlert: Codable, Hashable, Sendable {
    public var titleLocKey: String
    public var locKey: String
    public var locArgs: [String]?

    public init(titleLocKey: String, locKey: String, locArgs: [String]? = nil) {
        self.titleLocKey = titleLocKey
        self.locKey = locKey
        self.locArgs = locArgs
    }

    private enum CodingKeys: String, CodingKey {
        case titleLocKey = "title-loc-key"
        case locKey = "loc-key"
        case locArgs = "loc-args"
    }
}

/// The `aps` dictionary of an ordinary alert notification. No silent, critical or badge fields are ever set.
public struct PushAPS: Codable, Hashable, Sendable {
    public var alert: PushAlert
    public var category: String
    public var threadID: String
    public var sound: String
    /// `active` or `time-sensitive`.
    public var interruptionLevel: String

    public init(
        alert: PushAlert, category: String, threadID: String, sound: String = "default", interruptionLevel: String
    ) {
        self.alert = alert
        self.category = category
        self.threadID = threadID
        self.sound = sound
        self.interruptionLevel = interruptionLevel
    }

    private enum CodingKeys: String, CodingKey {
        case alert, category, sound
        case threadID = "thread-id"
        case interruptionLevel = "interruption-level"
    }
}

/// A complete push payload.
public struct PushPayload: Codable, Hashable, Sendable {
    /// APNs rejects larger payloads for ordinary notifications.
    public static let maxBytes = 4_096
    public var aps: PushAPS
    public var lisa: LisaPushData

    public init(aps: PushAPS, lisa: LisaPushData) {
        self.aps = aps
        self.lisa = lisa
    }

    /// Reads the `lisa` object from a delivered notification's user info, as JSON data.
    public static func lisaData(fromJSON data: Data) -> LisaPushData? {
        guard let payload = try? JSONDecoder().decode(PushPayload.self, from: data) else {
            struct Wrapper: Decodable { var lisa: LisaPushData }
            return (try? JSONDecoder().decode(Wrapper.self, from: data))?.lisa
        }
        return payload.lisa
    }
}
