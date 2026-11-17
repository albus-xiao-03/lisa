// The ideas screen: ideas from the host, capturing new ones through the durable queue, and editing, prioritizing,
// offering for planning and archiving them with revision checks.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The Mac app's ideas screen (UI-01: capture, edit, prioritize, schedule and archive; IDEA-01).
///
/// - The list comes from the host (`GET /v1/ideas`), optionally of one lifecycle stage. Ideas are not cached: while
///   the host is unreachable the screen keeps what it last read, marked as not current.
/// - Capturing goes through `capture`, the app's durable capture path: queued with a stable request ID and sent when
///   the host can be reached, so an idea captured offline is kept and never stored twice.
/// - Edits, priorities and stage changes expect the revision the owner saw (`PATCH /v1/ideas/{id}`). Scheduling an
///   idea offers it for planning: the host's planner proposes an exploration block, and accepting that block on the
///   rundown marks the idea scheduled. A proposed block never marks an idea explored (IDEA-01).
/// - When the idea changed on the host meanwhile, the change is a recoverable conflict (`conflicts`), shown with the
///   current idea; it is applied again only when the owner chooses to, and never overwrites the newer state silently.
/// - Idea changes are sent directly, not through the offline queue, which holds no idea changes: while the host
///   cannot be reached a change is `.unavailable` and nothing is saved, so the owner tries again later.
@MainActor
@Observable
public final class IdeasModel {
    /// What the screen shows.
    public private(set) var state: LoadState<Page<IdeaDTO>> = .idle
    /// The lifecycle stage the list shows, or `nil` for every idea.
    public private(set) var lifecycleFilter: IdeaLifecycleValue?
    /// Changes the host refused, by idea identifier, kept until the owner applies them again or discards them.
    public private(set) var conflicts: [String: IdeaConflict] = [:]
    /// Ideas with a change being sent.
    public private(set) var busyIdeaIDs: Set<String> = []
    /// Whether the next page is being read.
    public private(set) var isLoadingMore = false
    /// The outcome of the latest action.
    public private(set) var lastOutcome: ActionOutcome?
    /// The capture field of the screen; its draft is saved as an idea by `captureIdea()`.
    public let capture: CaptureModel

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// What the screen says when there are no ideas.
    public static let emptyMessage = "No ideas yet. Capture one to keep it for later."

    /// A model that reads and submits through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
        capture = CaptureModel(context: context, contacts: contacts)
    }

    /// The ideas shown.
    public var ideas: [IdeaDTO] { state.value?.items ?? [] }

    /// Whether the host has more ideas than the pages shown.
    public var hasMore: Bool { state.result?.value.nextCursor != nil }

    /// The idea shown with this identifier.
    public func idea(id: String) -> IdeaDTO? {
        ideas.first { $0.id == id }
    }

    /// The ideas shown whose summary matches `query`, every match kept.
    public func matches(for query: String) -> [IdeaDTO] {
        TitleMatcher.matches(query, in: ideas, title: \.summary)
    }

    // MARK: - Stages

    /// The stages an idea in `lifecycle` can move to, as the host allows them. The host stays the authority.
    public static func stages(after lifecycle: IdeaLifecycleValue) -> [IdeaLifecycleValue] {
        switch lifecycle {
        case .inbox: [.availableForPlanning, .archived]
        case .availableForPlanning: [.inbox, .scheduled, .explored, .archived]
        case .scheduled: [.availableForPlanning, .explored, .archived]
        case .explored: [.availableForPlanning, .archived]
        case .archived: [.inbox, .availableForPlanning]
        }
    }

    /// A name for `lifecycle`.
    public static func label(for lifecycle: IdeaLifecycleValue) -> String {
        switch lifecycle {
        case .inbox: "Inbox"
        case .availableForPlanning: "Ready for planning"
        case .scheduled: "Scheduled"
        case .explored: "Explored"
        case .archived: "Archived"
        }
    }

    /// Why the planner could not find time for `idea`, when it repeatedly could not (IDEA-01: the idea stays visible
    /// with the constraint); `nil` otherwise.
    public static func schedulingNote(for idea: IdeaDTO) -> String? {
        guard idea.unschedulableCount > 0 else { return nil }
        let times = idea.unschedulableCount == 1 ? "once" : "\(idea.unschedulableCount) times"
        guard let reason = idea.unschedulableReason, !reason.isEmpty else {
            return "Lisa couldn't find time for this \(times)."
        }
        return "Lisa couldn't find time for this \(times): \(reason)."
    }

    // MARK: - Reading

    /// Loads the first page of ideas, optionally only those in `lifecycle`.
    public func load(lifecycle: IdeaLifecycleValue? = nil) async {
        if lifecycle != lifecycleFilter { state = .idle }
        lifecycleFilter = lifecycle
        await refresh()
    }

    /// Reads the first page again. A refresh started later wins over an earlier one still running.
    public func refresh() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let lifecycle = lifecycleFilter
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<Page<IdeaDTO>> in
            ReadResult(value: try await client.ideas(lifecycle: lifecycle), fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        state = next
        for idea in ideas where conflicts[idea.id] != nil { conflicts[idea.id]?.current = idea }
    }

    /// Reads the next page from the host and appends it.
    public func loadMore() async {
        guard !isLoadingMore, let cursor = state.result?.value.nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do throws(ClientError) {
            let page = try await context.client.ideas(lifecycle: lifecycleFilter, cursor: cursor)
            await contacts?.record(.reached)
            guard current == generation else { return }
            state = state.updatingShown { shown in
                let known = Set(shown.items.map(\.id))
                shown.items += page.items.filter { !known.contains($0.id) }
                shown.nextCursor = page.nextCursor
            }
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    /// Reads one idea from the host and shows the current version, for example next to a refused change. The API has
    /// no route for a single idea, so the list is read until it is found.
    public func reloadIdea(id: String) async {
        let client = context.client
        do throws(ClientError) {
            let found = try await PageCollector.first(whose: \.id, is: id) {
                (cursor: String?) async throws(ClientError) -> Page<IdeaDTO> in
                try await client.ideas(limit: Pagination.maxLimit, cursor: cursor)
            }
            await contacts?.record(.reached)
            guard let found else { return }
            replace(found)
            conflicts[id]?.current = found
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
        }
    }

    // MARK: - Capturing

    /// Saves the capture draft as an idea through the durable queue (`CaptureModel.submit()`); once the host has it,
    /// the list is read again so it shows the new idea. A capture made offline is `.queued` and appears after it is
    /// sent.
    @discardableResult
    public func captureIdea() async -> ActionOutcome {
        if capture.draft.kind != .idea { capture.draft.kind = .idea }
        let outcome = await capture.submit()
        lastOutcome = outcome
        if outcome.isDone { await refresh() }
        return outcome
    }

    // MARK: - Changes

    /// Changes the details of `idea`, expecting the revision shown.
    @discardableResult
    public func edit(_ idea: IdeaDTO, _ edit: IdeaEdit) async -> ActionOutcome {
        if let problem = edit.problem { return refuse(problem) }
        return await send(idea.id, edit.patch(expectedRevision: idea.revision))
    }

    /// Sets the priority of `idea`, expecting the revision shown.
    @discardableResult
    public func setPriority(_ priority: TaskPriorityValue, of idea: IdeaDTO) async -> ActionOutcome {
        await send(idea.id, IdeaPatchRequest(expectedRevision: idea.revision, priority: priority))
    }

    /// Moves `idea` to the stage `lifecycle`, expecting the revision shown. Stages it cannot move to are refused before
    /// anything is sent (`stages(after:)`).
    @discardableResult
    public func move(_ idea: IdeaDTO, to lifecycle: IdeaLifecycleValue) async -> ActionOutcome {
        guard lifecycle != idea.lifecycle else {
            return refuse("the idea is already in \(Self.label(for: lifecycle))")
        }
        guard Self.stages(after: idea.lifecycle).contains(lifecycle) else {
            return refuse(
                "an idea in \(Self.label(for: idea.lifecycle)) can't move to \(Self.label(for: lifecycle))")
        }
        return await send(idea.id, IdeaPatchRequest(expectedRevision: idea.revision, lifecycle: lifecycle))
    }

    /// Schedules `idea` by offering it for planning: the host's planner proposes a block for it on a coming rundown.
    @discardableResult
    public func offerForPlanning(_ idea: IdeaDTO) async -> ActionOutcome {
        await move(idea, to: .availableForPlanning)
    }

    /// Archives `idea`.
    @discardableResult
    public func archive(_ idea: IdeaDTO) async -> ActionOutcome {
        await move(idea, to: .archived)
    }

    /// Moves an archived `idea` back to the inbox.
    @discardableResult
    public func restore(_ idea: IdeaDTO) async -> ActionOutcome {
        await move(idea, to: .inbox)
    }

    /// Marks `idea` as explored, once the owner has explored it.
    @discardableResult
    public func markExplored(_ idea: IdeaDTO) async -> ActionOutcome {
        await move(idea, to: .explored)
    }

    /// Applies a refused change again to the idea's current revision, after the owner has seen the current idea and
    /// chosen to keep the change.
    @discardableResult
    public func applyAgain(ideaID: String) async -> ActionOutcome {
        guard let refused = conflicts[ideaID] else { return refuse("there is no refused change for this idea") }
        guard let reported = refused.conflict.currentRevision else {
            return refuse("the idea can no longer take this change; discard it")
        }
        if let target = refused.change.lifecycle, let current = refused.current, target != current.lifecycle,
            !Self.stages(after: current.lifecycle).contains(target)
        {
            return refuse(
                "the idea is now in \(Self.label(for: current.lifecycle)) and can't move to \(Self.label(for: target))"
            )
        }
        var change = refused.change
        change.expectedRevision = refused.current?.revision ?? reported
        return await send(ideaID, change)
    }

    /// Discards a refused change; the idea stays as the host has it. Returns whether there was one.
    @discardableResult
    public func discardChange(ideaID: String) -> Bool {
        conflicts.removeValue(forKey: ideaID) != nil
    }

    // MARK: - Internals

    /// Sends one change with a new request ID and records its truthful outcome.
    private func send(_ ideaID: String, _ patch: IdeaPatchRequest) async -> ActionOutcome {
        busyIdeaIDs.insert(ideaID)
        defer { busyIdeaIDs.remove(ideaID) }
        let outcome: ActionOutcome
        do throws(ClientError) {
            let updated = try await context.client.updateIdea(id: ideaID, patch)
            await contacts?.record(.reached)
            replace(updated)
            conflicts[ideaID] = nil
            outcome = .done
            // The host plans after it answers and may record that an idea offered for planning cannot be scheduled,
            // which changes the idea's revision; reading it again lets the next change expect the current one.
            if updated.lifecycle == .availableForPlanning || updated.lifecycle == .scheduled {
                await reloadIdea(id: ideaID)
            }
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            hideDataIfRemoved(LoadFailure(error))
            outcome = ActionOutcome(unqueuedFailure: error)
            if case .conflict(let refusal) = outcome {
                conflicts[ideaID] = IdeaConflict(
                    ideaID: ideaID, conflict: refusal, change: patch, current: conflicts[ideaID]?.current)
                await reloadIdea(id: ideaID)
            }
        }
        lastOutcome = outcome
        return outcome
    }

    /// Reports an action refused before anything was sent.
    private func refuse(_ reason: String) -> ActionOutcome {
        let outcome = ActionOutcome.failed(reason: reason)
        lastOutcome = outcome
        return outcome
    }

    /// Stops showing the owner's ideas when the device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        state = .failed(failure, previous: nil)
        conflicts = [:]
    }

    /// Replaces a shown idea with its newer version.
    private func replace(_ idea: IdeaDTO) {
        state = state.updatingShown { shown in
            if let index = shown.items.firstIndex(where: { $0.id == idea.id }) { shown.items[index] = idea }
        }
    }
}
