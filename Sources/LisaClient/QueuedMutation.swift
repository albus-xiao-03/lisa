// The mutations the offline queue holds (UI-03, NOTIFY-05): their kinds, routes, bodies and expected revisions.

import Foundation
import LisaAPIContract

/// The kind of a queued mutation.
public enum QueuedMutationKind: String, Codable, Hashable, Sendable, CaseIterable {
    case capture
    case taskUpdate
    case reminderAction
    case notificationAction
    case proposalAction
    case planBlockAction
    case preferenceChange
    case notificationPreferenceChange
    case notificationReceipts
}

/// A mutation that can wait in the offline queue while the host is unreachable.
public enum QueuedMutation: Hashable, Sendable {
    /// `POST /v1/captures`.
    case capture(CaptureRequestDTO)
    /// `PATCH /v1/tasks/{id}`.
    case updateTask(id: String, TaskPatchRequest)
    /// `POST /v1/reminders/{id}/actions`.
    case reminderAction(id: String, ReminderActionRequest)
    /// `POST /v1/notifications/{id}/actions`.
    case notificationAction(notificationID: String, NotificationActionRequest)
    /// `POST /v1/event-proposals/{id}/actions`.
    case proposalAction(id: String, ProposalActionRequest)
    /// `POST /v1/plans/{planID}/blocks/{blockID}/actions`.
    case planBlockAction(planID: String, blockID: String, PlanBlockActionRequest)
    /// `PATCH /v1/preferences`.
    case updatePreferences(PreferencesPatchRequest)
    /// `PATCH /v1/devices/current/notification-preferences`.
    case updateNotificationPreferences(DeviceNotificationPreferencesPatch)
    /// `POST /v1/devices/current/notification-receipts`.
    case notificationReceipts(NotificationReceiptsRequest)

    /// The kind of the mutation, for display and decoding.
    public var kind: QueuedMutationKind {
        switch self {
        case .capture: .capture
        case .updateTask: .taskUpdate
        case .reminderAction: .reminderAction
        case .notificationAction: .notificationAction
        case .proposalAction: .proposalAction
        case .planBlockAction: .planBlockAction
        case .updatePreferences: .preferenceChange
        case .updateNotificationPreferences: .notificationPreferenceChange
        case .notificationReceipts: .notificationReceipts
        }
    }

    /// The route the mutation is sent to.
    public var route: APIRoute {
        switch self {
        case .capture: .capture
        case .updateTask(let id, _): .updateTask(id: id)
        case .reminderAction(let id, _): .reminderAction(id: id)
        case .notificationAction(let id, _): .notificationAction(id: id)
        case .proposalAction(let id, _): .proposalAction(id: id)
        case .planBlockAction(let planID, let blockID, _): .planBlockAction(planID: planID, blockID: blockID)
        case .updatePreferences: .updatePreferences
        case .updateNotificationPreferences: .updateDeviceNotificationPreferences
        case .notificationReceipts: .notificationReceipts
        }
    }

    /// The revision the mutation expects its subject to have, when it carries one.
    public var expectedRevision: Int64? {
        switch self {
        case .updateTask(_, let request): request.expectedRevision
        case .reminderAction(_, let request): request.expectedRevision
        case .proposalAction(_, let request): request.expectedRevision
        case .planBlockAction(_, _, let request): request.expectedRevision
        case .updatePreferences(let request): request.changes.count == 1 ? request.changes[0].expectedRevision : nil
        case .updateNotificationPreferences(let request): request.expectedRevision
        case .capture, .notificationAction, .notificationReceipts: nil
        }
    }

    /// The same mutation expecting `revision`, for re-queueing after a conflict. `nil` when the mutation has no single
    /// expected revision: captures, notification actions, receipts, and preference patches with several changes.
    public func expecting(revision: Int64) -> QueuedMutation? {
        switch self {
        case .updateTask(let id, var request):
            request.expectedRevision = revision
            return .updateTask(id: id, request)
        case .reminderAction(let id, var request):
            request.expectedRevision = revision
            return .reminderAction(id: id, request)
        case .proposalAction(let id, var request):
            request.expectedRevision = revision
            return .proposalAction(id: id, request)
        case .planBlockAction(let planID, let blockID, var request):
            request.expectedRevision = revision
            return .planBlockAction(planID: planID, blockID: blockID, request)
        case .updatePreferences(var request):
            guard request.changes.count == 1 else { return nil }
            request.changes[0].expectedRevision = revision
            return .updatePreferences(request)
        case .updateNotificationPreferences(var request):
            request.expectedRevision = revision
            return .updateNotificationPreferences(request)
        case .capture, .notificationAction, .notificationReceipts:
            return nil
        }
    }

    /// The request body, as `APIJSON.encoder()` encodes it.
    public func body() throws -> Data {
        let encoder = APIJSON.encoder()
        switch self {
        case .capture(let request): return try encoder.encode(request)
        case .updateTask(_, let request): return try encoder.encode(request)
        case .reminderAction(_, let request): return try encoder.encode(request)
        case .notificationAction(_, let request): return try encoder.encode(request)
        case .proposalAction(_, let request): return try encoder.encode(request)
        case .planBlockAction(_, _, let request): return try encoder.encode(request)
        case .updatePreferences(let request): return try encoder.encode(request)
        case .updateNotificationPreferences(let request): return try encoder.encode(request)
        case .notificationReceipts(let request): return try encoder.encode(request)
        }
    }

    /// Rebuilds a mutation from a queued kind, route and body.
    init(kind: QueuedMutationKind, route: APIRoute, body: Data) throws {
        let decoder = APIJSON.decoder()
        switch (kind, route) {
        case (.capture, .capture):
            self = .capture(try decoder.decode(CaptureRequestDTO.self, from: body))
        case (.taskUpdate, .updateTask(let id)):
            self = .updateTask(id: id, try decoder.decode(TaskPatchRequest.self, from: body))
        case (.reminderAction, .reminderAction(let id)):
            self = .reminderAction(id: id, try decoder.decode(ReminderActionRequest.self, from: body))
        case (.notificationAction, .notificationAction(let id)):
            self = .notificationAction(
                notificationID: id, try decoder.decode(NotificationActionRequest.self, from: body))
        case (.proposalAction, .proposalAction(let id)):
            self = .proposalAction(id: id, try decoder.decode(ProposalActionRequest.self, from: body))
        case (.planBlockAction, .planBlockAction(let planID, let blockID)):
            self = .planBlockAction(
                planID: planID, blockID: blockID, try decoder.decode(PlanBlockActionRequest.self, from: body))
        case (.preferenceChange, .updatePreferences):
            self = .updatePreferences(try decoder.decode(PreferencesPatchRequest.self, from: body))
        case (.notificationPreferenceChange, .updateDeviceNotificationPreferences):
            self = .updateNotificationPreferences(
                try decoder.decode(DeviceNotificationPreferencesPatch.self, from: body))
        case (.notificationReceipts, .notificationReceipts):
            self = .notificationReceipts(try decoder.decode(NotificationReceiptsRequest.self, from: body))
        default:
            throw OfflineQueueError.malformedEntry("a \(kind.rawValue) entry does not match its route")
        }
    }
}
