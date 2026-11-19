// One queued action as the pending-actions screen shows it: what it is, where it stands and why, without content.

import Foundation
import LisaAPIContract
import LisaClient

/// One entry of the offline queue as the pending-actions screen shows it (NOTIFY-05, UI-03): queued by the app, by
/// Siri, or by a notification action. `summary` and `message` never contain the owner's content; `mutation` holds the
/// details for the screen to show.
public struct PendingAction: Hashable, Sendable, Identifiable {
    /// The entry's stable identity.
    public var id: String
    /// The request ID the host sees on the next attempt.
    public var requestID: String
    /// What the action is.
    public var kind: QueuedMutationKind
    /// Where the entry stands.
    public var status: QueueEntryStatus
    /// A short description such as "Snooze reminder", without the owner's content.
    public var summary: String
    /// When the action was queued.
    public var queuedAt: Date
    /// How many times it was sent.
    public var attempts: Int
    /// When it was last sent.
    public var lastAttemptAt: Date?
    /// The earliest time it is sent again, after the host asked the device to wait.
    public var nextAttemptAt: Date?
    /// Whether an earlier attempt may already have been applied by the host (its answer was lost); check the item
    /// before submitting a failed one again.
    public var mayHaveBeenApplied: Bool
    /// Why the last attempt did not succeed, from the host or the connection.
    public var message: String?
    /// For a conflict, the subject's current revision on the host.
    public var currentRevision: Int64?
    /// Whether the owner took this action. Notification receipts are kept by the app itself and are not.
    public var isOwnerAction: Bool
    /// The queued mutation, for showing its details; `nil` when it cannot be read.
    public var mutation: QueuedMutation?

    /// The view of a queued entry.
    public init(_ entry: QueuedRequest) {
        id = entry.id
        requestID = entry.requestID
        kind = entry.kind
        status = entry.status
        queuedAt = entry.createdAt
        attempts = entry.attempts
        lastAttemptAt = entry.lastAttemptAt
        nextAttemptAt = entry.nextAttemptAt
        mayHaveBeenApplied = entry.uncertainSince != nil
        message = entry.lastError?.message
        currentRevision = entry.serverRevision
        isOwnerAction = entry.kind != .notificationReceipts
        mutation = try? entry.mutation()
        summary = Self.summary(kind: entry.kind, mutation: mutation)
    }

    /// Whether the entry still waits for the host.
    public var isPending: Bool { status == .pending || status == .sending }

    /// Whether the owner must resolve the entry: a conflict or a failure.
    public var needsResolution: Bool { status == .conflict || status == .failed }

    private static func summary(kind: QueuedMutationKind, mutation: QueuedMutation?) -> String {
        switch mutation {
        case .capture(let request)?: return capture(request.kind)
        case .updateTask(_, let patch)?:
            switch patch.status {
            case .completed?: return "Complete task"
            case .open?: return "Reopen task"
            case .some: return "Change task status"
            case nil: return "Edit task"
            }
        case .reminderAction(_, let request)?: return "\(verb(request.action)) reminder"
        case .notificationAction(_, let request)?: return "\(verb(request.action)) from a notification"
        default: break
        }
        switch kind {
        case .capture: return "Capture"
        case .taskUpdate: return "Change task"
        case .reminderAction: return "Reminder action"
        case .notificationAction: return "Notification action"
        case .proposalAction: return "Review event proposal"
        case .planBlockAction: return "Plan block action"
        case .preferenceChange: return "Change preference"
        case .notificationPreferenceChange: return "Change notification settings"
        case .notificationReceipts: return "Notification receipts"
        }
    }

    private static func capture(_ kind: CaptureKindValue) -> String {
        switch kind {
        case .idea: "Capture idea"
        case .text: "Save text"
        case .link: "Save link"
        case .sharedAppleNews: "Save Apple News share"
        }
    }

    private static func verb(_ action: ReminderActionKind) -> String {
        switch action {
        case .acknowledge: "Acknowledge"
        case .snooze: "Snooze"
        case .dismiss: "Dismiss"
        case .complete: "Complete"
        }
    }
}
