// Owner and device commands on the facade, each followed by its cross-service consequences and answering with its
// record as stored once those are done.

import Foundation
import LisaAgenda
import LisaDelivery
import LisaDevices
import LisaDomain
import LisaOwnerData
import LisaPorts
import LisaReview

extension LisaApplication {
    // MARK: - Captures, tasks and ideas

    public func capture(_ request: CaptureRequest, by principal: Principal) throws -> CaptureResult {
        try services.captures.capture(request, by: principal)
    }

    /// Reads the page behind a link the owner captured, once, and keeps it on the capture's news item (NEWS-01). Only
    /// the owner on the host and paired devices may ask; see `CapturedPageService`.
    public func retrieveCapturedPage(_ id: CaptureID, by principal: Principal) async throws -> CapturedPageOutcome {
        try CapturedPageService.authorize(principal)
        guard let pages = services.capturedPages else {
            throw CapturedPageError.unavailable("this host cannot read captured links")
        }
        return try await pages.retrieve(id, by: principal)
    }

    public func createTask(_ draft: TaskDraft, by principal: Principal) throws -> LisaTask {
        let update = try services.tasks.create(draft, by: principal)
        try propagate(update.changes)
        return try latest(update.task)
    }

    public func correctTask(
        _ id: TaskID, expectedRevision: Revision, _ correction: TaskCorrection, by principal: Principal
    )
        throws -> LisaTask
    {
        let update = try services.tasks.correct(id, expectedRevision: expectedRevision, correction, by: principal)
        try propagate(update.changes)
        return try latest(update.task)
    }

    /// Completes, cancels, reopens or starts a task. Completion and cancellation suppress pending deliveries for the
    /// task on every device and cancel its future reminders.
    public func setTaskStatus(_ id: TaskID, to status: TaskStatus, expectedRevision: Revision?, by principal: Principal)
        throws -> LisaTask
    {
        let update = try services.tasks.transition(id, to: status, expectedRevision: expectedRevision, by: principal)
        try propagate(update.changes)
        return try latest(update.task)
    }

    public func editIdea(_ id: IdeaID, expectedRevision: Revision, _ edit: IdeaEdit, by principal: Principal) throws
        -> Idea
    {
        let idea = try services.ideas.edit(id, expectedRevision: expectedRevision, edit, by: principal)
        try propagate([.ideaChanged(id)])
        return try latest(idea)
    }

    public func moveIdea(
        _ id: IdeaID, to lifecycle: IdeaLifecycle, expectedRevision: Revision?, by principal: Principal
    )
        throws -> Idea
    {
        let idea = try services.ideas.transition(id, to: lifecycle, expectedRevision: expectedRevision, by: principal)
        try propagate([.ideaChanged(id)])
        return try latest(idea)
    }

    // MARK: - Reminders and notification actions

    /// Applies a reminder action. "Complete" also completes the underlying task; acknowledgement never does.
    public func actOnReminder(
        _ action: ReminderAction, _ id: ReminderID, expectedRevision: Revision?, by principal: Principal
    )
        throws -> Reminder
    {
        let reminder = try services.reminders.act(action, on: id, expectedRevision: expectedRevision, by: principal)
        if action == .complete, case .task(let taskID) = reminder.subject {
            let task = try store.read { try $0.require(LisaTask.self, id: taskID) }
            if task.status.isActive {
                _ = try setTaskStatus(taskID, to: .completed, expectedRevision: nil, by: principal)
            }
        }
        return try latest(reminder)
    }

    /// An action submitted from a notification (plan §6.5), identified by the payload's notification ID.
    public func actOnNotification(_ action: ReminderAction, notificationID: NotificationID, by principal: Principal)
        throws
    {
        let intent = try store.read { try $0.require(NotificationIntent.self, id: notificationID) }
        if case .pairedDevice(let deviceID) = principal {
            try recordReceipt(notificationID: notificationID, deviceID: deviceID)
        }
        switch intent.subject {
        case .reminder(let reminderID):
            _ = try actOnReminder(action, reminderID, expectedRevision: nil, by: principal)
        case .occurrence, .task, .proposal, .brief:
            guard action == .acknowledge || action == .dismiss else {
                throw DomainError.notPermitted("this notification supports only opening and acknowledging")
            }
            let now = clock.now()
            try store.write { tx in
                try NotificationService.resolve(
                    subjectKeys: [intent.subject.key], reason: "acknowledged", at: now, in: tx)
                try tx.insert(
                    AuditEvent(
                        action: "notification.acknowledged", actor: principal, at: now,
                        affected: [notificationID.rawValue],
                        outcome: .succeeded, detail: intent.category.rawValue))
            }
        }
    }

    /// A device reports that a notification was presented: the only source of "confirmed delivered".
    public func recordReceipt(notificationID: NotificationID, deviceID: DeviceID) throws {
        let now = clock.now()
        try store.write { tx in
            _ = try DeliveryOutbox.recordReceipt(notificationID: notificationID, deviceID: deviceID, at: now, in: tx)
        }
    }

    // MARK: - Proposals, plans and briefs

    public func reviewProposal(
        _ action: ProposalAction, _ id: ProposalID, expectedRevision: Revision, by principal: Principal
    )
        throws -> EventProposal
    {
        let (proposal, change) = try services.proposals.apply(
            action, to: id, expectedRevision: expectedRevision, by: principal)
        try propagate([change])
        return try latest(proposal)
    }

    public func actOnPlanBlock(
        _ action: PlanBlockAction, planID: PlanID, blockID: String, expectedRevision: Revision, by principal: Principal
    ) throws -> Plan {
        let plan = try services.plans.act(
            action, planID: planID, blockID: blockID, expectedRevision: expectedRevision, by: principal)
        try services.reminders.sync()
        return plan
    }

    /// Moves a plan block to `start`–`end` (PLAN-04). The block becomes owner-held there, its day is replanned around it
    /// and its reminders follow it. A move that breaks a rule throws `PlanBlockMoveRefusal` and changes nothing.
    public func movePlanBlock(
        planID: PlanID, blockID: String, start: Date, end: Date, expectedRevision: Revision, by principal: Principal
    ) throws -> Plan {
        let plan = try services.plans.move(
            planID: planID, blockID: blockID, start: start, end: end, expectedRevision: expectedRevision,
            by: principal)
        try services.reminders.sync()
        return try latest(plan)
    }

    // MARK: - Preferences, deletion and export

    public func setPreference(
        _ key: PreferenceKey, _ value: PreferenceValue, expectedRevision: Revision?, by principal: Principal
    )
        throws -> Preference
    {
        let (preference, change) = try services.preferences.set(
            key, value, expectedRevision: expectedRevision, by: principal)
        try propagate([change])
        return try latest(preference)
    }

    public func confirmPreference(_ key: PreferenceKey, by principal: Principal) throws -> Preference {
        let (preference, change) = try services.preferences.confirm(key, by: principal)
        try propagate([change])
        return try latest(preference)
    }

    public func delete(_ item: DeletableItem, by principal: Principal) throws -> DeletionResult {
        let result = try services.deletion.delete(item, by: principal)
        if case .task(let id) = item {
            try services.reminders.cancelAll(subjectKey: "task:\(id.rawValue)", reason: "the task was deleted")
        }
        try propagate(result.changes)
        return result
    }

    // MARK: - Devices

    /// Pairing codes are created only by the owner on the host.
    public func createPairingCode(by principal: Principal) throws -> PairingCode {
        guard principal == .localOwner else { throw DomainError.notPermitted("pairing codes are created on the host") }
        return services.devices.createPairingCode()
    }

    /// Revokes a device: its credential stops working and its pending deliveries are cancelled. A device may remove
    /// itself; only the owner may remove another device.
    public func revokeDevice(_ id: DeviceID, by principal: Principal) throws -> DeviceRegistration {
        switch principal {
        case .localOwner, .demonstration: break
        case .pairedDevice(let caller) where caller == id: break
        default: throw DomainError.notPermitted("only the owner can remove another device")
        }
        let device = try services.devices.revoke(deviceID: id, by: principal)
        let now = clock.now()
        try store.write { tx in
            _ = try DeliveryOutbox.cancelPending(
                recipient: .device(id), reason: "the device was removed", at: now, in: tx)
        }
        return device
    }

    // MARK: - Results

    /// `record` as stored now. A command's consequences (replanning, matching, reminder changes) may change the record
    /// it just saved, so answering with the saved copy would hand the caller an outdated revision; `record` itself is
    /// returned when it is no longer stored.
    private func latest<E: StoredEntity>(_ record: E) throws -> E {
        try self.record(E.self, id: record.id) ?? record
    }
}
