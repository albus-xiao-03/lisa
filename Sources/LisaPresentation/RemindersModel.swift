// The reminders screen: active reminders from the host, acknowledged or snoozed through the durable queue.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The reminders screen (UI-02) and the reminder action Siri uses (SIRI-01: snooze a selected reminder).
///
/// - The list holds the host's active reminders (scheduled, delivered and snoozed). Reminders are not cached, so
///   while the host is unreachable the screen keeps the reminders it last read, marked as not current.
/// - Acknowledging and snoozing expect the revision shown. Each action is queued durably with a stable request ID and
///   sent at once when possible; offline it stays pending. Snoozing uses the host's configured snooze duration and
///   the host computes the next reminder (plan §6.5).
/// - When the reminder changed on the host meanwhile, the action is a recoverable conflict (`conflicts`), never
///   applied over the newer state without the owner choosing to.
@MainActor
@Observable
public final class RemindersModel {
    /// What the screen shows.
    public private(set) var state: LoadState<[ReminderDTO]> = .idle
    /// Actions waiting in the offline queue, by reminder identifier.
    public private(set) var pendingActions: [String: ReminderActionKind] = [:]
    /// Actions the host refused because the reminder changed, by reminder identifier.
    public private(set) var conflicts: [String: ActionConflict] = [:]
    /// Reminders with an action being submitted.
    public private(set) var busyReminderIDs: Set<String> = []
    /// The outcome of the latest action.
    public private(set) var lastOutcome: ActionOutcome?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// A model that reads and submits through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    /// The reminders shown.
    public var reminders: [ReminderDTO] { state.value ?? [] }

    /// The reminders shown whose title matches `query`, every match kept for disambiguation (SIRI-01).
    public func matches(for query: String) -> [ReminderDTO] {
        TitleMatcher.matches(query, in: reminders, title: \.title)
    }

    /// Reads the active reminders and the queued actions. A load started later wins over an earlier one.
    public func load() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<[ReminderDTO]> in
            let page = try await client.reminders(limit: Pagination.maxLimit)
            return ReadResult(value: page.items, fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        state = next
        await syncQueue()
    }

    /// Acknowledges `reminder`, expecting the revision shown. Acknowledging never completes the task.
    @discardableResult
    public func acknowledge(_ reminder: ReminderDTO) async -> ActionOutcome {
        await act(.acknowledge, on: reminder)
    }

    /// Snoozes `reminder` for the host's configured snooze duration, expecting the revision shown.
    @discardableResult
    public func snooze(_ reminder: ReminderDTO) async -> ActionOutcome {
        await act(.snooze, on: reminder)
    }

    /// Applies a refused action again to the reminder's current revision, after the owner has seen the current
    /// reminder and chosen to.
    @discardableResult
    public func applyAgain(reminderID: String) async -> ActionOutcome {
        guard let conflict = conflicts[reminderID], let entryID = conflict.entryID,
            let revision = conflict.currentRevision
        else { return .failed(reason: "this action can no longer be applied; discard it") }
        busyReminderIDs.insert(reminderID)
        defer { busyReminderIDs.remove(reminderID) }
        return await finish(await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
    }

    /// Discards a refused action; the reminder stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardAction(reminderID: String) async -> Bool {
        guard let entryID = conflicts[reminderID]?.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Internals

    private func act(_ action: ReminderActionKind, on reminder: ReminderDTO) async -> ActionOutcome {
        busyReminderIDs.insert(reminder.id)
        defer { busyReminderIDs.remove(reminder.id) }
        let request = ReminderActionRequest(action: action, expectedRevision: reminder.revision)
        return await finish(await ActionSubmitter(context: context).submit(.reminderAction(id: reminder.id, request)))
    }

    private func finish(_ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked {
            // The host removed this device: stop showing the owner's reminders.
            generation += 1
            state = .failed(.revoked, previous: nil)
        }
        if let updated = submission.decoded(ReminderDTO.self) { replace(updated) }
        await syncQueue()
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Replaces a shown reminder with its newer version.
    private func replace(_ reminder: ReminderDTO) {
        guard var shown = state.result, let index = shown.value.firstIndex(where: { $0.id == reminder.id }) else {
            return
        }
        shown.value[index] = reminder
        switch state {
        case .loaded: state = .loaded(shown)
        case .loading: state = .loading(previous: shown)
        case .failed(let failure, _): state = .failed(failure, previous: shown)
        case .idle: break
        }
    }

    /// Reads the reminder actions waiting in the queue and those the host refused.
    private func syncQueue() async {
        let queue = context.queue
        var pending: [String: ReminderActionKind] = [:]
        for entry in await queue.pendingEntries where entry.kind == .reminderAction {
            guard case .reminderAction(let id, let request)? = try? entry.mutation() else { continue }
            pending[id] = request.action
        }
        var refused: [String: ActionConflict] = [:]
        for entry in await queue.conflictEntries where entry.kind == .reminderAction {
            guard case .reminderAction(let id, _)? = try? entry.mutation(), let conflict = ActionConflict(entry: entry)
            else { continue }
            refused[id] = conflict
        }
        pendingActions = pending
        conflicts = refused
    }
}
