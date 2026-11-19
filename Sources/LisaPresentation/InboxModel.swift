// The inbox: event proposals and extracted tasks waiting for the owner's review; decisions, corrections and
// confirmations are queued durably with revision checks, and conflicts are recoverable.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The Mac app's inbox (UI-01: extracted items and event proposals needing review).
///
/// - **Event proposals** whose calendar match is unresolved (EVENT-01): they need clarification, were not found in the
///   subscribed calendars, or may match an event there. The owner confirms a possible match, dismisses a proposal,
///   corrects its details, or saves its calendar file (`calendarFile(for:)`) and then reports having added it. Saving
///   the file never counts as adding the event; Lisa never writes to a calendar.
/// - **Extracted tasks** the host marked as possible commitments (`origin == "extracted"`, `confirmation ==
///   .possible`) that are still open, in progress or blocked. The owner confirms one, corrects it (confirming it unless
///   asked not to), or dismisses it, which cancels the task.
/// - Every action expects the revision the owner saw, is queued durably with a stable request ID and is sent at once
///   when possible; offline it stays pending. When the item changed on the host meanwhile, the action is a recoverable
///   conflict shown with the current item. It is applied again only when the owner chooses to, and it never
///   overwrites the newer state silently.
/// - The inbox is not cached: while the host is unreachable the screen keeps what it last read, marked as not current.
@MainActor
@Observable
public final class InboxModel {
    /// The event proposals the inbox read.
    public private(set) var proposals: LoadState<[EventProposalDTO]> = .idle
    /// The extracted tasks the inbox read.
    public private(set) var tasks: LoadState<[TaskDTO]> = .idle
    /// Whether the host holds more items than the inbox reads at once; the screen then says it shows the first ones.
    public private(set) var isIncomplete = false
    /// Proposal actions waiting in the offline queue, by proposal identifier.
    public private(set) var pendingProposalActions: [String: ProposalActionRequest] = [:]
    /// Proposal actions the host refused because the proposal changed, by proposal identifier.
    public private(set) var proposalConflicts: [String: ProposalConflict] = [:]
    /// Changes of the inbox's tasks waiting in the offline queue, by task identifier.
    public private(set) var pendingTaskChanges: [String: TaskPatchRequest] = [:]
    /// Changes of the inbox's tasks the host refused because the task changed, by task identifier.
    public private(set) var taskConflicts: [String: TaskConflict] = [:]
    /// Proposals and tasks with an action being submitted.
    public private(set) var busyItemIDs: Set<String> = []
    /// The outcome of the latest action.
    public private(set) var lastOutcome: ActionOutcome?
    /// Why the latest calendar file could not be read, if it could not.
    public private(set) var calendarFileFailure: LoadFailure?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// The match states of proposals that need the owner's review.
    public static let reviewStates = ["needsClarification", "notFound", "possibleMatch"]
    /// What the screen says when nothing needs review.
    public static let emptyMessage = "Nothing needs your review."
    /// The task states in which an extracted task can still need review.
    static let activeStatuses: [TaskStatusValue] = [.open, .inProgress, .blocked]

    /// A model that reads and submits through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    // MARK: - What the screen shows

    /// The proposals shown that still need review.
    public var proposalsToReview: [EventProposalDTO] { (proposals.value ?? []).filter(Self.needsReview) }

    /// The tasks shown that still need review.
    public var tasksToReview: [TaskDTO] { (tasks.value ?? []).filter(Self.needsReview) }

    /// How many items need review.
    public var reviewCount: Int { proposalsToReview.count + tasksToReview.count }

    /// Whether both lists were read and nothing needs review; the screen then shows `emptyMessage`.
    public var isEmpty: Bool { proposals.value != nil && tasks.value != nil && reviewCount == 0 }

    /// The proposal shown with this identifier.
    public func proposal(id: String) -> EventProposalDTO? {
        proposals.value?.first { $0.id == id }
    }

    /// The task shown with this identifier.
    public func task(id: String) -> TaskDTO? {
        tasks.value?.first { $0.id == id }
    }

    /// Whether `proposal` still needs the owner's review.
    public static func needsReview(_ proposal: EventProposalDTO) -> Bool {
        reviewStates.contains(proposal.match.state)
    }

    /// Whether `task` is an extracted possible commitment that is still open, in progress or blocked.
    public static func needsReview(_ task: TaskDTO) -> Bool {
        task.origin == "extracted" && task.confirmation == .possible && activeStatuses.contains(task.status)
    }

    /// Whether `proposal` has a possible calendar match the owner can confirm.
    public static func canConfirmMatch(_ proposal: EventProposalDTO) -> Bool {
        proposal.match.state == "possibleMatch" && proposal.match.occurrenceID != nil
    }

    /// Whether `proposal` has a time or a date, so it can be saved as a calendar file.
    public static func canSaveCalendarFile(_ proposal: EventProposalDTO) -> Bool {
        !proposal.timing.isUnknown
    }

    /// Where `proposal` stands, as a sentence for its row and its accessible label.
    public static func reviewStatus(of proposal: EventProposalDTO) -> String {
        switch proposal.match.state {
        case "needsClarification":
            proposal.match.detail.map { "Needs details: \($0)." } ?? "Needs details before Lisa can check it."
        case "notFound": "Not found in your calendars."
        case "possibleMatch": "May already be on your calendar."
        case "matched": "On your calendar."
        case "dismissed": "Dismissed."
        case "ownerReportsAdded": "You added it. Lisa looks for it when your calendar refreshes."
        default: "Waiting for review."
        }
    }

    // MARK: - Reading

    /// Reads the proposals and extracted tasks needing review, and the queued actions. A load started later wins over
    /// an earlier one still running.
    public func load() async {
        generation += 1
        let current = generation
        let previousProposals = proposals.result
        let previousTasks = tasks.result
        proposals = .loading(previous: previousProposals)
        tasks = .loading(previous: previousTasks)
        let client = context.client
        let now = context.now
        var incomplete = false
        let nextProposals = await ReadRunner.load(previous: previousProposals, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<[EventProposalDTO]> in
            let collected = try await PageCollector.collect {
                (cursor: String?) async throws(ClientError) -> Page<EventProposalDTO> in
                try await client.proposals(states: Self.reviewStates, limit: Pagination.maxLimit, cursor: cursor)
            }
            if !collected.isComplete { incomplete = true }
            return ReadResult(value: collected.items, fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        let nextTasks: LoadState<[TaskDTO]>
        if let failure = nextProposals.failure, failure.hidesData {
            // The device is not paired or was removed: the tasks are not read, and the screen shows one reason.
            nextTasks = .failed(failure, previous: nil)
        } else {
            nextTasks = await ReadRunner.load(previous: previousTasks, contacts: contacts) {
                () async throws(ClientError) -> ReadResult<[TaskDTO]> in
                var found: [TaskDTO] = []
                for status in Self.activeStatuses {
                    let collected = try await PageCollector.collect {
                        (cursor: String?) async throws(ClientError) -> Page<TaskDTO> in
                        try await client.tasks(status: status, limit: Pagination.maxLimit, cursor: cursor)
                    }
                    if !collected.isComplete { incomplete = true }
                    found += collected.items.filter(Self.needsReview)
                }
                return ReadResult(value: found, fetchedAt: now(), source: .host)
            }
        }
        guard current == generation else { return }
        proposals = nextProposals
        tasks = nextTasks
        isIncomplete = incomplete
        await syncQueue()
    }

    /// Reads one proposal from the host, whatever its state, and shows the current version, for example next to a
    /// refused action. The API has no route for a single proposal, so the list is read until it is found.
    public func reloadProposal(id: String) async {
        let client = context.client
        do throws(ClientError) {
            let found = try await PageCollector.first(whose: \.id, is: id) {
                (cursor: String?) async throws(ClientError) -> Page<EventProposalDTO> in
                try await client.proposals(limit: Pagination.maxLimit, cursor: cursor)
            }
            await contacts?.record(.reached)
            guard let found else { return }
            replace(found)
            proposalConflicts[id]?.current = found
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    /// Reads one task from the host and shows the current version, for example next to a refused change.
    public func reloadTask(id: String) async {
        do throws(ClientError) {
            let fetched = try await context.client.task(id: id)
            await contacts?.record(.reached)
            replace(fetched)
            taskConflicts[id]?.current = fetched
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    /// The proposal as iCalendar (`.ics`) text, for the owner to save and add to a calendar themselves; `nil` with
    /// `calendarFileFailure` saying why when it cannot be read. Saving it does not mark the event as added: the owner
    /// reports that with `reportAdded(_:)` once it is on a calendar.
    public func calendarFile(for proposal: EventProposalDTO) async -> String? {
        guard Self.canSaveCalendarFile(proposal) else {
            calendarFileFailure = .failed(reason: "the proposal has no date or time yet; correct it first")
            return nil
        }
        do throws(ClientError) {
            let text = try await context.client.proposalCalendarFile(id: proposal.id)
            await contacts?.record(.reached)
            calendarFileFailure = nil
            return text
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            let failure = LoadFailure(error)
            hideDataIfRemoved(failure)
            calendarFileFailure = failure
            return nil
        }
    }

    // MARK: - Proposal actions

    /// Confirms that `proposal` is the calendar event it may match, expecting the revision shown.
    @discardableResult
    public func confirmMatch(_ proposal: EventProposalDTO) async -> ActionOutcome {
        guard Self.canConfirmMatch(proposal), let occurrenceID = proposal.match.occurrenceID else {
            return refuse("this proposal has no possible calendar match to confirm")
        }
        return await submit(
            proposal.id,
            ProposalActionRequest(
                action: .confirmMatch, expectedRevision: proposal.revision, occurrenceID: occurrenceID))
    }

    /// Dismisses `proposal`, expecting the revision shown.
    @discardableResult
    public func dismiss(_ proposal: EventProposalDTO) async -> ActionOutcome {
        await submit(proposal.id, ProposalActionRequest(action: .dismiss, expectedRevision: proposal.revision))
    }

    /// Records that the owner added `proposal` to a calendar themselves; Lisa then looks for it when the calendar
    /// subscription refreshes. Expects the revision shown.
    @discardableResult
    public func reportAdded(_ proposal: EventProposalDTO) async -> ActionOutcome {
        await submit(proposal.id, ProposalActionRequest(action: .reportAdded, expectedRevision: proposal.revision))
    }

    /// Corrects the details of `proposal`, expecting the revision shown.
    @discardableResult
    public func correct(_ proposal: EventProposalDTO, _ correction: ProposalCorrection) async -> ActionOutcome {
        if let problem = correction.problem { return refuse(problem) }
        return await submit(proposal.id, correction.request(expectedRevision: proposal.revision))
    }

    /// Applies a refused proposal action again to the proposal's current revision, after the owner has seen the
    /// current proposal and chosen to keep the action.
    @discardableResult
    public func applyAgain(proposalID: String) async -> ActionOutcome {
        guard let conflict = proposalConflicts[proposalID], let entryID = conflict.conflict.entryID else {
            return refuse("there is no refused action for this proposal")
        }
        guard let reported = conflict.conflict.currentRevision else {
            return refuse("the proposal can no longer take this action; discard it")
        }
        busyItemIDs.insert(proposalID)
        defer { busyItemIDs.remove(proposalID) }
        let revision = conflict.current?.revision ?? reported
        let outcome = await finishProposal(
            proposalID, await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
        await reloadIfMatchedAfterwards(conflict.action?.action, proposalID: proposalID, outcome: outcome)
        return outcome
    }

    /// Discards a refused proposal action; the proposal stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardAction(proposalID: String) async -> Bool {
        guard let entryID = proposalConflicts[proposalID]?.conflict.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Task actions

    /// Confirms `task` as the owner's commitment, expecting the revision shown.
    @discardableResult
    public func confirm(_ task: TaskDTO) async -> ActionOutcome {
        await submitTask(task.id, TaskPatchRequest(expectedRevision: task.revision, confirmation: .confirmed))
    }

    /// Dismisses `task` as not the owner's commitment: the task is cancelled. Expects the revision shown.
    @discardableResult
    public func dismiss(_ task: TaskDTO) async -> ActionOutcome {
        await submitTask(task.id, TaskPatchRequest(expectedRevision: task.revision, status: .cancelled))
    }

    /// Corrects the details of `task` and, unless `confirming` is `false`, confirms it in the same change. Expects the
    /// revision shown. An empty correction only confirms.
    @discardableResult
    public func correct(_ task: TaskDTO, _ edit: TaskEdit, confirming: Bool = true) async -> ActionOutcome {
        if edit.isEmpty, confirming { return await confirm(task) }
        if let problem = edit.problem { return refuse(problem) }
        var patch = edit.patch(expectedRevision: task.revision)
        if confirming { patch.confirmation = .confirmed }
        return await submitTask(task.id, patch)
    }

    /// Applies a refused task change again to the task's current revision, after the owner has seen the current task
    /// and chosen to keep the change.
    @discardableResult
    public func applyAgain(taskID: String) async -> ActionOutcome {
        guard let conflict = taskConflicts[taskID], let entryID = conflict.conflict.entryID else {
            return refuse("there is no refused change for this task")
        }
        guard let revision = conflict.current?.revision ?? conflict.conflict.currentRevision else {
            return refuse("the task's current version is unknown; refresh the inbox and try again")
        }
        busyItemIDs.insert(taskID)
        defer { busyItemIDs.remove(taskID) }
        return await finishTask(
            taskID, await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
    }

    /// Discards a refused task change; the task stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardChange(taskID: String) async -> Bool {
        guard let entryID = taskConflicts[taskID]?.conflict.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Internals

    private func submit(_ proposalID: String, _ request: ProposalActionRequest) async -> ActionOutcome {
        busyItemIDs.insert(proposalID)
        defer { busyItemIDs.remove(proposalID) }
        let submission = await ActionSubmitter(context: context).submit(.proposalAction(id: proposalID, request))
        let outcome = await finishProposal(proposalID, submission)
        await reloadIfMatchedAfterwards(request.action, proposalID: proposalID, outcome: outcome)
        return outcome
    }

    /// Reads the proposal again after a correction or an "added" report the host applied. The host matches proposals
    /// against the calendars after it answers, which can change the proposal's state and revision; reading it again
    /// shows the current state and lets the next action expect the current revision.
    private func reloadIfMatchedAfterwards(
        _ action: ProposalActionKind?, proposalID: String, outcome: ActionOutcome
    ) async {
        guard outcome.isDone, action == .correct || action == .reportAdded else { return }
        await reloadProposal(id: proposalID)
    }

    private func submitTask(_ taskID: String, _ patch: TaskPatchRequest) async -> ActionOutcome {
        busyItemIDs.insert(taskID)
        defer { busyItemIDs.remove(taskID) }
        let submission = await ActionSubmitter(context: context).submit(
            .updateTask(id: taskID, patch), coalescing: true)
        return await finishTask(taskID, submission)
    }

    /// Records a proposal submission: the connectivity it showed, the updated proposal and the queue's state; a
    /// conflict also reads the current proposal so the owner can review it.
    private func finishProposal(_ id: String, _ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked { hideDataIfRemoved(.revoked) }
        if let updated = submission.decoded(EventProposalDTO.self) { replace(updated) }
        await syncQueue()
        if case .conflict = submission.outcome { await reloadProposal(id: id) }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Records a task submission like `finishProposal(_:_:)`.
    private func finishTask(_ id: String, _ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked { hideDataIfRemoved(.revoked) }
        if let updated = submission.decoded(TaskDTO.self) { replace(updated) }
        await syncQueue()
        if case .conflict = submission.outcome { await reloadTask(id: id) }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Reports an action refused before anything was sent.
    private func refuse(_ reason: String) -> ActionOutcome {
        let outcome = ActionOutcome.failed(reason: reason)
        lastOutcome = outcome
        return outcome
    }

    /// Stops showing the owner's items when the device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        proposals = .failed(failure, previous: nil)
        tasks = .failed(failure, previous: nil)
    }

    /// Replaces a shown proposal with its newer version.
    private func replace(_ proposal: EventProposalDTO) {
        proposals = proposals.updatingShown { shown in
            if let index = shown.firstIndex(where: { $0.id == proposal.id }) { shown[index] = proposal }
        }
    }

    /// Replaces a shown task with its newer version.
    private func replace(_ task: TaskDTO) {
        tasks = tasks.updatingShown { shown in
            if let index = shown.firstIndex(where: { $0.id == task.id }) { shown[index] = task }
        }
    }

    /// Reads the proposal actions and the changes of the inbox's tasks that wait in the queue or were refused.
    private func syncQueue() async {
        let queue = context.queue
        let shownTasks = Set((tasks.value ?? []).map(\.id))
        var actions: [String: ProposalActionRequest] = [:]
        var changes: [String: TaskPatchRequest] = [:]
        for entry in await queue.pendingEntries {
            switch try? entry.mutation() {
            case .proposalAction(let id, let request)?: actions[id] = request
            case .updateTask(let id, let patch)? where shownTasks.contains(id): changes[id] = patch
            default: continue
            }
        }
        var refusedProposals: [String: ProposalConflict] = [:]
        var refusedTasks: [String: TaskConflict] = [:]
        for entry in await queue.conflictEntries {
            guard let conflict = ActionConflict(entry: entry) else { continue }
            switch try? entry.mutation() {
            case .proposalAction(let id, let request)?:
                refusedProposals[id] = ProposalConflict(
                    proposalID: id, conflict: conflict, action: request, current: proposalConflicts[id]?.current)
            case .updateTask(let id, let patch)? where shownTasks.contains(id):
                refusedTasks[id] = TaskConflict(
                    taskID: id, conflict: conflict, change: patch, current: taskConflicts[id]?.current)
            default: continue
            }
        }
        pendingProposalActions = actions
        pendingTaskChanges = changes
        proposalConflicts = refusedProposals
        taskConflicts = refusedTasks
    }
}
