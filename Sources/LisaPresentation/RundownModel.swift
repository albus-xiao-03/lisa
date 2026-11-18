// The rundown screen: today's or a chosen date's plan from the host, or the cached copy with its age while offline;
// the owner's actions on its blocks and moves of them, queued durably against the plan revision shown; and the
// rundown read aloud.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The rundown screen (UI-02) and the plan on the Mac's Today (UI-01).
///
/// - While the host is unreachable the screen shows the cached rundown with its age, never as current (UI-03); when no
///   date is chosen, that may be an earlier day's rundown (`showsEarlierDay`). A device that is not paired, or that the
///   host removed, shows no rundown. Refreshing is explicit: nothing polls the host.
/// - The owner accepts, locks, declines, defers or completes a block (PLAN-04) with `act(_:on:)`, and moves one to a
///   new start and end with `move(_:to:)`, expecting the plan revision shown. `PlanBlockActions` says which actions a
///   block offers; calendar events offer none. Each action is queued durably with a stable request ID and sent at
///   once when possible; offline it stays pending (`pendingBlockActions`, and the new times of a move in
///   `requestedMoves`). Once the host applies it, the screen shows the plan as the host answered it. A move the host
///   refuses, because the new time would overlap a busy calendar event or another block the owner holds or leave the
///   rundown's day, is `.failed` with the host's reason, and nothing changed.
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
    /// The new times that moves waiting in the queue or refused because the plan changed ask for, by block identifier.
    /// A block's refused action counts before its waiting one, as `blockConflicts` and `pendingBlockActions` are
    /// shown. The plan shown keeps the block's times until the host applies the move.
    public private(set) var requestedMoves: [String: PlanBlockTimes] = [:]
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
            requestedMoves = [:]
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
    /// is sent. A move needs the block's new times: `move(_:to:)`.
    @discardableResult
    public func act(_ action: PlanBlockActionKind, on block: PlanBlockDTO) async -> ActionOutcome {
        guard let plan = state.value, let shown = plan.blocks.first(where: { $0.blockID == block.blockID }) else {
            return refuse("this block isn't in the rundown shown; refresh the rundown and try again")
        }
        if let refusal = PlanBlockActions.refusal(of: action, on: shown) { return refuse(refusal) }
        guard action != .move else { return refuse("choose the block's new start and end to move it") }
        let request = PlanBlockActionRequest(action: action, expectedRevision: plan.revision)
        return await submit(request, on: shown, of: plan)
    }

    /// Moves `block` of the plan shown to `times`, taken to the minute as time pickers show them, expecting the plan
    /// revision shown (PLAN-04).
    ///
    /// The host locks the block at its new time, so planning again keeps it there, and plans the rest of the day
    /// around it; the screen then shows the plan as the host answered it. The host refuses a move that would overlap a
    /// busy calendar event or another block the owner accepted, locked or completed, or that leaves the rundown's day:
    /// the outcome is `.failed` with the host's reason, and nothing changed. A block that is no longer shown, one that
    /// cannot be moved (`PlanBlockActions.canMove(_:)`) and times whose end is not after their start are refused before
    /// anything is sent. Offline, the move waits in the queue like the other actions (`requestedMoves`).
    @discardableResult
    public func move(_ block: PlanBlockDTO, to times: PlanBlockTimes) async -> ActionOutcome {
        guard let plan = state.value, let shown = plan.blocks.first(where: { $0.blockID == block.blockID }) else {
            return refuse("this block isn't in the rundown shown; refresh the rundown and try again")
        }
        if let refusal = PlanBlockActions.refusal(of: .move, on: shown) { return refuse(refusal) }
        let picked = times.toTheMinute
        guard picked.isOrdered else { return refuse("the new end must be after the new start") }
        let request = PlanBlockActionRequest(
            action: .move, expectedRevision: plan.revision, start: picked.start, end: picked.end)
        return await submit(request, on: shown, of: plan)
    }

    /// Applies a refused action again to the plan shown, after the owner has seen the block as that plan has it and
    /// chosen to keep the action. It expects the revision shown, so a plan that changed again is another conflict. A
    /// refused move is applied again with the times the owner picked, which the host checks against the plan shown.
    @discardableResult
    public func applyAgain(blockID: String) async -> ActionOutcome {
        guard let refused = blockConflicts[blockID], let entryID = refused.conflict.entryID else {
            return refuse("there is no refused action for this block")
        }
        guard Self.canApplyAgain(refused), let plan = state.value, plan.planID == refused.planID else {
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

    /// Queues `request` for `block` of `plan` and tries to send it now; the block is busy meanwhile.
    private func submit(_ request: PlanBlockActionRequest, on block: PlanBlockDTO, of plan: RundownDTO) async
        -> ActionOutcome
    {
        busyBlockIDs.insert(block.blockID)
        defer { busyBlockIDs.remove(block.blockID) }
        let submission = await ActionSubmitter(context: context).submit(
            .planBlockAction(planID: plan.planID, blockID: block.blockID, request))
        return await finish(submission)
    }

    /// Whether a refused action can be applied again: it is still queued, its block is still in the plan shown, and
    /// the block still offers it (`PlanBlockActions.offers(_:on:)`, which includes moving). For the actions taken in
    /// one step this is `PlanBlockConflict.canApplyAgain`.
    private static func canApplyAgain(_ refused: PlanBlockConflict) -> Bool {
        guard refused.conflict.entryID != nil, let current = refused.current else { return false }
        return PlanBlockActions.offers(refused.action, on: current)
    }

    /// The new times a move asks for; `nil` for the other actions.
    private static func times(of request: PlanBlockActionRequest) -> PlanBlockTimes? {
        guard request.action == .move, let start = request.start, let end = request.end else { return nil }
        return PlanBlockTimes(start: start, end: end)
    }

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
            requestedMoves = [:]
            return
        }
        var pending: [String: PlanBlockActionKind] = [:]
        var waitingMoves: [String: PlanBlockTimes] = [:]
        for entry in waiting where entry.kind == .planBlockAction {
            guard case .planBlockAction(let planID, let blockID, let request)? = try? entry.mutation(),
                planID == plan.planID
            else { continue }
            pending[blockID] = request.action
            waitingMoves[blockID] = Self.times(of: request)
        }
        var refused: [String: PlanBlockConflict] = [:]
        var refusedMoves: [String: PlanBlockTimes] = [:]
        for entry in refusedEntries where entry.kind == .planBlockAction {
            guard case .planBlockAction(let planID, let blockID, let request)? = try? entry.mutation(),
                planID == plan.planID, let conflict = ActionConflict(entry: entry)
            else { continue }
            refused[blockID] = PlanBlockConflict(
                planID: planID, blockID: blockID, action: request.action, conflict: conflict,
                current: plan.blocks.first { $0.blockID == blockID })
            refusedMoves[blockID] = Self.times(of: request)
        }
        pendingBlockActions = pending
        blockConflicts = refused
        // A block's mark stands for its refused action when it has one, otherwise for its waiting one.
        var moves = waitingMoves.filter { refused[$0.key] == nil }
        moves.merge(refusedMoves) { _, refusedTimes in refusedTimes }
        requestedMoves = moves
    }
}
