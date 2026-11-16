// Every v1 route (API-02 plus documented extensions), with path building for clients and matching for the router.

import Foundation

/// A v1 operation and its path parameters.
public enum APIRoute: Hashable, Sendable {
    case health
    case rundown
    case planBlockAction(planID: String, blockID: String)
    case brief
    case regenerateBrief
    case capture
    case listTasks
    case createTask
    case task(id: String)
    case updateTask(id: String)
    case listIdeas
    case updateIdea(id: String)
    case listProposals
    case proposalAction(id: String)
    case proposalCalendarFile(id: String)
    case listReminders
    case reminderAction(id: String)
    case notificationAction(id: String)
    case preferences
    case updatePreferences
    case sourcesStatus
    case createPairingCode
    case pairDevice
    case pushRegistration
    case notificationStatus
    case deviceNotificationPreferences
    case updateDeviceNotificationPreferences
    case notificationReceipts
    case listDevices
    case removeDevice(id: String)
    case export

    public var method: HTTPMethod {
        switch self {
        case .health, .rundown, .brief, .listTasks, .task, .listIdeas, .listProposals, .proposalCalendarFile,
            .listReminders, .preferences, .sourcesStatus, .deviceNotificationPreferences, .listDevices, .export:
            .get
        case .planBlockAction, .regenerateBrief, .capture, .createTask, .proposalAction, .reminderAction,
            .notificationAction, .createPairingCode, .pairDevice, .notificationReceipts:
            .post
        case .pushRegistration, .notificationStatus: .put
        case .updateTask, .updateIdea, .updatePreferences, .updateDeviceNotificationPreferences: .patch
        case .removeDevice: .delete
        }
    }

    public var path: String {
        let prefix = APIVersioning.pathPrefix
        switch self {
        case .health: return "\(prefix)/health"
        case .rundown: return "\(prefix)/rundown"
        case .planBlockAction(let plan, let block):
            return "\(prefix)/plans/\(Self.escape(plan))/blocks/\(Self.escape(block))/actions"
        case .brief: return "\(prefix)/brief"
        case .regenerateBrief: return "\(prefix)/briefs/regenerate"
        case .capture: return "\(prefix)/captures"
        case .listTasks, .createTask: return "\(prefix)/tasks"
        case .task(let id), .updateTask(let id): return "\(prefix)/tasks/\(Self.escape(id))"
        case .listIdeas: return "\(prefix)/ideas"
        case .updateIdea(let id): return "\(prefix)/ideas/\(Self.escape(id))"
        case .listProposals: return "\(prefix)/event-proposals"
        case .proposalAction(let id): return "\(prefix)/event-proposals/\(Self.escape(id))/actions"
        case .proposalCalendarFile(let id): return "\(prefix)/event-proposals/\(Self.escape(id))/calendar-file"
        case .listReminders: return "\(prefix)/reminders"
        case .reminderAction(let id): return "\(prefix)/reminders/\(Self.escape(id))/actions"
        case .notificationAction(let id): return "\(prefix)/notifications/\(Self.escape(id))/actions"
        case .preferences, .updatePreferences: return "\(prefix)/preferences"
        case .sourcesStatus: return "\(prefix)/sources/status"
        case .createPairingCode: return "\(prefix)/devices/pairing-codes"
        case .pairDevice: return "\(prefix)/devices/pair"
        case .pushRegistration: return "\(prefix)/devices/current/push-registration"
        case .notificationStatus: return "\(prefix)/devices/current/notification-status"
        case .deviceNotificationPreferences, .updateDeviceNotificationPreferences:
            return "\(prefix)/devices/current/notification-preferences"
        case .notificationReceipts: return "\(prefix)/devices/current/notification-receipts"
        case .listDevices: return "\(prefix)/devices"
        case .removeDevice(let id): return "\(prefix)/devices/\(Self.escape(id))"
        case .export: return "\(prefix)/export"
        }
    }

    /// Whether the route changes state and therefore requires a request ID.
    public var isMutation: Bool { method != .get }

    /// The route for an incoming method and path, or `nil` when none matches.
    public static func match(method: HTTPMethod, path: String) -> APIRoute? {
        var segments = path.split(separator: "/", omittingEmptySubsequences: true).map {
            String($0).removingPercentEncoding ?? String($0)
        }
        guard segments.first == "v1" else { return nil }
        segments.removeFirst()
        switch (method, segments.count) {
        case (.get, 1):
            switch segments[0] {
            case "health": return .health
            case "rundown": return .rundown
            case "brief": return .brief
            case "tasks": return .listTasks
            case "ideas": return .listIdeas
            case "event-proposals": return .listProposals
            case "reminders": return .listReminders
            case "preferences": return .preferences
            case "devices": return .listDevices
            case "export": return .export
            default: return nil
            }
        case (.post, 1):
            switch segments[0] {
            case "captures": return .capture
            case "tasks": return .createTask
            default: return nil
            }
        case (.patch, 1): return segments[0] == "preferences" ? .updatePreferences : nil
        case (.get, 2):
            if segments[0] == "tasks" { return .task(id: segments[1]) }
            if segments == ["sources", "status"] { return .sourcesStatus }
            return nil
        case (.post, 2):
            if segments == ["briefs", "regenerate"] { return .regenerateBrief }
            if segments == ["devices", "pair"] { return .pairDevice }
            if segments == ["devices", "pairing-codes"] { return .createPairingCode }
            return nil
        case (.patch, 2):
            if segments[0] == "tasks" { return .updateTask(id: segments[1]) }
            if segments[0] == "ideas" { return .updateIdea(id: segments[1]) }
            return nil
        case (.delete, 2): return segments[0] == "devices" ? .removeDevice(id: segments[1]) : nil
        case (.get, 3):
            if segments[0] == "event-proposals", segments[2] == "calendar-file" {
                return .proposalCalendarFile(id: segments[1])
            }
            if segments == ["devices", "current", "notification-preferences"] { return .deviceNotificationPreferences }
            return nil
        case (.post, 3):
            guard segments[2] == "actions" || segments[1] == "current" else { return nil }
            switch segments[0] {
            case "event-proposals": return .proposalAction(id: segments[1])
            case "reminders": return .reminderAction(id: segments[1])
            case "notifications": return .notificationAction(id: segments[1])
            case "devices" where segments[1] == "current" && segments[2] == "notification-receipts":
                return .notificationReceipts
            default: return nil
            }
        case (.put, 3):
            guard segments[0] == "devices", segments[1] == "current" else { return nil }
            if segments[2] == "push-registration" { return .pushRegistration }
            if segments[2] == "notification-status" { return .notificationStatus }
            return nil
        case (.patch, 3):
            return segments == ["devices", "current", "notification-preferences"]
                ? .updateDeviceNotificationPreferences : nil
        case (.post, 5):
            guard segments[0] == "plans", segments[2] == "blocks", segments[4] == "actions" else { return nil }
            return .planBlockAction(planID: segments[1], blockID: segments[3])
        default:
            return nil
        }
    }

    static func escape(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

/// A page of results. Pass `nextCursor` back as the `cursor` query parameter to continue.
public struct Page<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public var items: [Item]
    public var nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

/// Pagination limits (API-03).
public enum Pagination {
    public static let defaultLimit = 50
    public static let maxLimit = 200
    public static let limitParameter = "limit"
    public static let cursorParameter = "cursor"
}
