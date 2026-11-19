// The tasks screen: the task list from the host or the cache, and task changes queued durably with revision checks.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The tasks screen (UI-02) and the task actions Siri uses (SIRI-01: mark a selected task complete).
///
/// - The list is read through the cache: while the host is unreachable the cached first page is shown with its age,
///   never as current (UI-03).
/// - Completing, reopening and editing a task always expect the revision the owner saw. Each change is queued durably
///   with a stable request ID and sent at once when possible; offline it stays pending (`pendingChanges`), and two
///   offline changes of one task that the host cannot have applied yet are merged into one.
/// - When the task changed on the host meanwhile, the change is a recoverable conflict (`conflicts`), shown with the
///   current task; it is applied again only when the owner chooses to, and never overwrites the newer state silently.
@MainActor
@Observable
public final class TasksModel {
    /// What the screen shows.
    public private(set) var state: LoadState<Page<TaskDTO>> = .idle
    /// The status filter of the list, or `nil` for every task.
    public private(set) var statusFilter: TaskStatusValue?
    /// Changes waiting in the offline queue, by task identifier.
    public private(set) var pendingChanges: [String: TaskPatchRequest] = [:]
    /// Changes the host refused because the task changed, by task identifier.
    public private(set) var conflicts: [String: TaskConflict] = [:]
    /// Tasks with a change being submitted.
    public private(set) var busyTaskIDs: Set<String> = []
    /// Whether the next page is being read.
    public private(set) var isLoadingMore = false
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

    /// The tasks shown.
    public var tasks: [TaskDTO] { state.value?.items ?? [] }

    /// Whether the host has more tasks than the pages shown; only a list read from the host can be continued.
    public var hasMore: Bool {
        guard let result = state.result, result.source == .host else { return false }
        return result.value.nextCursor != nil
    }

    /// The task shown with this identifier.
    public func task(id: String) -> TaskDTO? {
        tasks.first { $0.id == id }
    }

    /// The tasks shown whose title matches `query`, every match kept for disambiguation (SIRI-01).
    public func matches(for query: String) -> [TaskDTO] {
        TitleMatcher.matches(query, in: tasks, title: \.title)
    }

    // MARK: - Reading

    /// Loads the first page of tasks, optionally only those with `status`.
    public func load(status: TaskStatusValue? = nil) async {
        if status != statusFilter { state = .idle }
        statusFilter = status
        await refresh()
    }

    /// Reads the first page again and the queued changes. A refresh started later wins over an earlier one.
    public func refresh() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let reader = context.reader
        let status = statusFilter
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<Page<TaskDTO>> in
            try await reader.tasks(status: status)
        }
        guard current == generation else { return }
        state = next
        await syncQueue()
    }

    /// Reads the next page from the host and appends it.
    public func loadMore() async {
        guard !isLoadingMore, hasMore, let result = state.result, let cursor = result.value.nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do throws(ClientError) {
            let page = try await context.client.tasks(status: statusFilter, cursor: cursor)
            await contacts?.record(.reached)
            guard current == generation, var shown = state.result else { return }
            let known = Set(shown.value.items.map(\.id))
            shown.value.items += page.items.filter { !known.contains($0.id) }
            shown.value.nextCursor = page.nextCursor
            state = .loaded(shown)
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    /// Fetches one task from the host, for example to review a conflict, and shows the current version.
    public func reloadTask(id: String) async {
        do throws(ClientError) {
            let fetched = try await context.client.task(id: id)
            await contacts?.record(.reached)
            replace(fetched)
            conflicts[id]?.current = fetched
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    // MARK: - Changes

    /// Marks `task` complete, expecting the revision shown.
    @discardableResult
    public func complete(_ task: TaskDTO) async -> ActionOutcome {
        await setStatus(.completed, of: task)
    }

    /// Reopens `task`, expecting the revision shown.
    @discardableResult
    public func reopen(_ task: TaskDTO) async -> ActionOutcome {
        await setStatus(.open, of: task)
    }

    /// Sets the status of `task`, expecting the revision shown.
    @discardableResult
    public func setStatus(_ status: TaskStatusValue, of task: TaskDTO) async -> ActionOutcome {
        await submit(task.id, TaskPatchRequest(expectedRevision: task.revision, status: status))
    }

    /// Changes the details of `task`, expecting the revision shown.
    @discardableResult
    public func edit(_ task: TaskDTO, _ edit: TaskEdit) async -> ActionOutcome {
        if let problem = edit.problem {
            lastOutcome = .failed(reason: problem)
            return .failed(reason: problem)
        }
        return await submit(task.id, edit.patch(expectedRevision: task.revision))
    }

    /// Applies a refused change again to the task's current revision, after the owner has seen the current task and
    /// chosen to keep the change.
    @discardableResult
    public func applyAgain(taskID: String) async -> ActionOutcome {
        guard let conflict = conflicts[taskID], let entryID = conflict.conflict.entryID else {
            return .failed(reason: "there is no refused change for this task")
        }
        guard let revision = conflict.current?.revision ?? conflict.conflict.currentRevision else {
            return .failed(reason: "the task's current version is unknown; refresh the task and try again")
        }
        busyTaskIDs.insert(taskID)
        defer { busyTaskIDs.remove(taskID) }
        return await finish(
            taskID, await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
    }

    /// Discards a refused change; the task stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardChange(taskID: String) async -> Bool {
        guard let entryID = conflicts[taskID]?.conflict.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Internals

    private func submit(_ taskID: String, _ patch: TaskPatchRequest) async -> ActionOutcome {
        busyTaskIDs.insert(taskID)
        defer { busyTaskIDs.remove(taskID) }
        let submission = await ActionSubmitter(context: context).submit(
            .updateTask(id: taskID, patch), coalescing: true)
        return await finish(taskID, submission)
    }

    /// Records a submission: the connectivity it showed, the updated task, and the queue's pending changes and
    /// conflicts; a conflict also fetches the current task so the owner can review it.
    private func finish(_ taskID: String, _ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked { hideDataIfRemoved(.revoked) }
        if let updated = submission.decoded(TaskDTO.self) { replace(updated) }
        await syncQueue()
        if case .conflict = submission.outcome { await reloadTask(id: taskID) }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Stops showing the owner's tasks when the device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        state = .failed(failure, previous: nil)
    }

    /// Replaces a shown task with its newer version.
    private func replace(_ task: TaskDTO) {
        guard var shown = state.result, let index = shown.value.items.firstIndex(where: { $0.id == task.id }) else {
            return
        }
        shown.value.items[index] = task
        switch state {
        case .loaded: state = .loaded(shown)
        case .loading: state = .loading(previous: shown)
        case .failed(let failure, _): state = .failed(failure, previous: shown)
        case .idle: break
        }
    }

    /// Reads the task changes waiting in the queue and those the host refused.
    private func syncQueue() async {
        let queue = context.queue
        var changes: [String: TaskPatchRequest] = [:]
        for entry in await queue.pendingEntries where entry.kind == .taskUpdate {
            guard case .updateTask(let id, let patch)? = try? entry.mutation() else { continue }
            changes[id] = patch
        }
        var refused: [String: TaskConflict] = [:]
        for entry in await queue.conflictEntries where entry.kind == .taskUpdate {
            guard case .updateTask(let id, let patch)? = try? entry.mutation(),
                let conflict = ActionConflict(entry: entry)
            else { continue }
            refused[id] = TaskConflict(taskID: id, conflict: conflict, change: patch, current: conflicts[id]?.current)
        }
        pendingChanges = changes
        conflicts = refused
    }
}
