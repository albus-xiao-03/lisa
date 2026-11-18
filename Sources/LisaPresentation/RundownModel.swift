// The rundown screen: today's or a chosen date's plan from the host, or the cached copy with its age while offline;
// the owner's actions on its blocks, queued durably against the plan revision shown; and the rundown read aloud.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The rundown screen (UI-02) and the plan on the Mac's Today (UI-01).
///
/// - While the host is unreachable the screen shows the cached rundown with its age, never as current (UI-03); when no
///   date is chosen, that may be an earlier day's rundown (`showsEarlierDay`). A device that is not paired, or that the
///   host removed, shows no rundown. Refreshing is explicit: nothing polls the host.
/// - The owner accepts, locks, declines, defers or completes a block (PLAN-04) with `act(_:on:)`, expecting the plan
///   revision shown. `PlanBlockActions` says which actions a block offers; calendar events offer none. Each action is
///   queued durably with a stable request ID and sent at once when possible; offline it stays pending
///   (`pendingBlockActions`). Once the host applies it, the screen shows the plan as the host answered it.
/// - Every applied action gives the plan a new revision. An action that expects an earlier one, because the planner,
///   another device or an earlier queued action changed the plan first, is a recoverable conflict (`blockConflicts`),
///   shown with the block as the current plan has it. Two offline actions on one plan are not merged, so the second is
///   such a conflict. A refused action is applied again only when the owner chooses to, never over the newer plan
///   silently.
/// - `speechText(at:locale:)` is the rundown read aloud. Whenever the rundown shown is not the host's current answer, it
///   starts with the rundown's day and age.
@MainActor
@Observable
public final class RundownModel {
    /// What the screen shows.
    public private(set) var state: LoadState<RundownDTO> = .idle
    /// The date shown (`YYYY-MM-DD`), or `nil` for the host's current date.
    public private(set) var date: String?
    /// Actions on blocks of the plan shown that wait in the offline queue, by block identifier.
    public private(set) var pendingBlockActions: [String: PlanBlockActionKind] = [:]
    /// Actions on blocks of the plan shown that the host refused because the plan changed, by block identifier.
    public private(set) var blockConflicts: [String: PlanBlockConflict] = [:]
    /// Blocks with an action being submitted.
    public private(set) var busyBlockIDs: Set<String> = []
    /// The outcome of the latest block action.
    public private(set) var lastOutcome: ActionOutcome?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// A model that reads and submits through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    // MARK: - Reading

    /// Loads the rundown of `date` (`YYYY-MM-DD`), or of the host's current date.
    public func load(date: String? = nil) async {
        if date != self.date {
            state = .idle
            pendingBlockActions = [:]
            blockConflicts = [:]
        }
        self.date = date
        await refresh()
    }

    /// Reads the shown date's rundown again, and the block actions in the queue. A refresh started later wins over an
    /// earlier one still running.
    public func refresh() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let reader = context.reader
        let date = date
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<RundownDTO> in
            try await reader.rundown(date: date)
        }
        guard current == generation else { return }
        state = next
        await syncQueue()
    }

    /// Whether the rundown shown is a cached copy of a day before this device's current date, shown because the host
    /// could not say which day is current.
    public var showsEarlierDay: Bool {
        guard date == nil, let result = state.result, result.source == .cache else { return false }
        return LocalDay.isBefore(result.value.date, dayOf: context.now(), in: context.timeZone)
    }

    // MARK: - Reading aloud

    /// What to say for "read the rundown" at `now` (`RundownSpeech`): the planned blocks with their start times in
    /// `locale`'s format, preceded by the rundown's day and age whenever it is not the host's current answer: a saved
    /// copy, an earlier day's, or the plan kept on screen after a refresh failed. `nil` when no rundown is shown;
    /// `state.failure` then says why.
    public func speechText(at now: Date, locale: Locale = .current) -> String? {
        guard let result = state.result else { return nil }
        return RundownSpeech.text(
            for: result, at: now, isCurrent: !(state.isStale || showsEarlierDay), timeZone: context.timeZone,
            locale: locale)
    }

    // MARK: - Block actions

    /// Applies `action` to `block` of the plan shown, expecting the plan revision shown. A block that is no longer
    /// shown, and an action the block does not offer (`PlanBlockActions.available(for:)`), are refused before anything
    /// is sent.
    @discardableResult
    public func act(_ action: PlanBlockActionKind, on block: PlanBlockDTO) async -> ActionOutcome {
        guard let plan = state.value, let shown = plan.blocks.first(where: { $0.blockID == block.blockID }) else {
            return refuse("this block isn't in the rundown shown; refresh the rundown and try again")
        }
        if let refusal = PlanBlockActions.refusal(of: action, on: shown) { return refuse(refusal) }
        busyBlockIDs.insert(shown.blockID)
        defer { busyBlockIDs.remove(shown.blockID) }
        let request = PlanBlockActionRequest(action: action, expectedRevision: plan.revision)
        let submission = await ActionSubmitter(context: context).submit(
            .planBlockAction(planID: plan.planID, blockID: shown.blockID, request))
        return await finish(submission)
    }

    /// Applies a refused action again to the plan shown, after the owner has seen the block as that plan has it and
    /// chosen to keep the action. It expects the revision shown, so a plan that changed again is another conflict.
    @discardableResult
    public func applyAgain(blockID: String) async -> ActionOutcome {
        guard let refused = blockConflicts[blockID], let entryID = refused.conflict.entryID else {
            return refuse("there is no refused action for this block")
        }
        guard refused.canApplyAgain, let plan = state.value, plan.planID == refused.planID else {
            return refuse("the block can no longer take this action; discard it")
        }
        busyBlockIDs.insert(blockID)
        defer { busyBlockIDs.remove(blockID) }
        return await finish(
            await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: plan.revision))
    }

    /// Discards a refused action; the plan stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardAction(blockID: String) async -> Bool {
        guard let entryID = blockConflicts[blockID]?.conflict.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    // MARK: - Internals

    /// Records a submission: the connectivity it showed, the plan the host answered with, and the queue's pending
    /// actions and conflicts. A conflict reads the rundown again instead, so the owner sees the current plan.
    private func finish(_ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked { hideDataIfRemoved(.revoked) }
        if case .conflict = submission.outcome {
            await refresh()
        } else if let answered = submission.decoded(RundownDTO.self) {
            await show(answered)
        } else {
            await syncQueue()
        }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Shows `plan`, the host's answer to an action, and caches it as its day's rundown unless a newer revision is
    /// cached already. The answer replaces an earlier revision of the plan shown when that came from the host. A saved
    /// copy shown instead may be an earlier day's, so the shown date's rundown is read from the host again.
    private func show(_ plan: RundownDTO) async {
        let fetchedAt = context.now()
        let cached = try? await context.cache.rundown(for: plan.date)
        let cachedIsNewer = cached.map { $0.value.planID == plan.planID && $0.value.revision > plan.revision } ?? false
        if !cachedIsNewer { _ = try? await context.cache.store(plan, fetchedAt: fetchedAt) }
        guard let shown = state.result, shown.value.planID == plan.planID, shown.value.revision <= plan.revision else {
            await syncQueue()
            return
        }
        guard shown.source == .host else {
            await refresh()
            return
        }
        let answered = ReadResult(value: plan, fetchedAt: fetchedAt, source: .host)
        state = state.isLoading ? .loading(previous: answered) : .loaded(answered)
        await syncQueue()
    }

    /// Reports an action refused before anything was sent.
    private func refuse(_ reason: String) -> ActionOutcome {
        let outcome = ActionOutcome.failed(reason: reason)
        lastOutcome = outcome
        return outcome
    }

    /// Stops showing the owner's plan when the device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        state = .failed(failure, previous: nil)
    }

    /// Reads the actions on blocks of the plan shown that wait in the queue and those the host refused.
    private func syncQueue() async {
        let queue = context.queue
        let waiting = await queue.pendingEntries
        let refusedEntries = await queue.conflictEntries
        guard let plan = state.value else {
            pendingBlockActions = [:]
            blockConflicts = [:]
            return
        }
        var pending: [String: PlanBlockActionKind] = [:]
        for entry in waiting where entry.kind == .planBlockAction {
            guard case .planBlockAction(let planID, let blockID, let request)? = try? entry.mutation(),
                planID == plan.planID
            else { continue }
            pending[blockID] = request.action
        }
        var refused: [String: PlanBlockConflict] = [:]
        for entry in refusedEntries where entry.kind == .planBlockAction {
            guard case .planBlockAction(let planID, let blockID, let request)? = try? entry.mutation(),
                planID == plan.planID, let conflict = ActionConflict(entry: entry)
            else { continue }
            refused[blockID] = PlanBlockConflict(
                planID: planID, blockID: blockID, action: request.action, conflict: conflict,
                current: plan.blocks.first { $0.blockID == blockID })
        }
        pendingBlockActions = pending
        blockConflicts = refused
    }
}
