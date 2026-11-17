// The memory screen: the owner's preferences from the host, explicit and inferred, set, confirmed and deleted through
// the durable queue, with the host's refusals shown next to each preference.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The Mac app's memory screen (UI-01: inspect and edit preferences; MEM-01) and the delivery preferences of the
/// settings screen.
///
/// - The list is the host's stored preferences (`GET /v1/preferences`): explicit values, and inferred ones, which take
///   effect only once the owner confirms them (`inferredAwaitingConfirmation`). Consequential keys (`consequential`:
///   recipients, the phone number, email and call enablement, model settings, the Time Sensitive opt-in) are changed
///   only by the owner on the host, which the Mac app is; the host refuses them from a paired device.
/// - Each change of one preference is its own request (`PATCH /v1/preferences`), so the host's answer belongs to that
///   preference. It expects the revision shown, is queued durably with a stable request ID and is sent at once when
///   possible; offline it stays pending (`pendingChanges`).
/// - A refused value is shown next to its preference with the host's message (`issues`), and the value shown stays the
///   host's. A change refused because the preference changed meanwhile is a recoverable conflict (`conflicts`), never
///   applied over the newer value without the owner choosing to.
/// - Preferences are not cached: while the host is unreachable the screen keeps what it last read, marked as not
///   current.
@MainActor
@Observable
public final class MemoryModel {
    /// What the screen shows.
    public private(set) var state: LoadState<[PreferenceDTO]> = .idle
    /// Changes waiting in the offline queue, by key.
    public private(set) var pendingChanges: [String: PreferenceChange] = [:]
    /// Changes the host refused because the preference changed, by key.
    public private(set) var conflicts: [String: PreferenceConflict] = [:]
    /// Changes the host refused for their value or for permission, by key, with the host's message.
    public private(set) var issues: [String: PreferenceIssue] = [:]
    /// Keys with a change being submitted.
    public private(set) var busyKeys: Set<String> = []
    /// The outcome of the latest change.
    public private(set) var lastOutcome: ActionOutcome?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// What the screen says when no preference is stored.
    public static let emptyMessage = "No preferences are saved yet. Lisa follows its configuration until you set one."

    /// A model that reads and submits through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    // MARK: - What the screen shows

    /// The preferences shown, in key order.
    public var preferences: [PreferenceDTO] { state.value ?? [] }

    /// The preference shown with this key.
    public func preference(key: String) -> PreferenceDTO? {
        preferences.first { $0.key == key }
    }

    /// The preferences shown that belong to `group` (`PreferenceDescriptor.describing(_:)`).
    public func preferences(in group: PreferenceDescriptor.Group) -> [PreferenceDTO] {
        preferences.filter { PreferenceDescriptor.describing($0.key).group == group }
    }

    /// Inferred preferences that take effect only once the owner confirms them.
    public var inferredAwaitingConfirmation: [PreferenceDTO] {
        preferences.filter { $0.origin == "inferred" && !$0.confirmed }
    }

    /// The value to show for `key` with its queued change applied: the queued value, `nil` while a deletion is
    /// queued, otherwise the host's value. `pendingChanges` tells which keys are not confirmed by the host yet.
    public func displayedValue(for key: String) -> PreferenceValueDTO? {
        if let change = pendingChanges[key], change.confirm != true { return change.value }
        return preference(key: key)?.value
    }

    // MARK: - Reading

    /// Reads the preferences and the queued changes. A load started later wins over an earlier one still running.
    public func load() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let client = context.client
        let now = context.now
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<[PreferenceDTO]> in
            ReadResult(value: try await client.preferences(), fetchedAt: now(), source: .host)
        }
        guard current == generation else { return }
        state = next
        await syncQueue()
    }

    // MARK: - Changes

    /// Sets `key` to `value`, expecting the revision shown when the preference exists. A value the host refuses is
    /// recorded in `issues` with the host's message.
    @discardableResult
    public func set(_ key: String, to value: PreferenceValueDTO) async -> ActionOutcome {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return refuse("enter the name of the preference") }
        return await submit(PreferenceChange(key: key, value: value, expectedRevision: preference(key: key)?.revision))
    }

    /// Confirms an inferred preference so it takes effect, without changing its value.
    @discardableResult
    public func confirm(_ key: String) async -> ActionOutcome {
        guard let preference = preference(key: key) else { return refuse("there is no such preference") }
        guard preference.origin == "inferred", !preference.confirmed else {
            return refuse("only an inferred preference waits for confirmation")
        }
        return await submit(PreferenceChange(key: key, confirm: true, expectedRevision: preference.revision))
    }

    /// Deletes a preference; Lisa then follows its configuration for it again.
    @discardableResult
    public func delete(_ key: String) async -> ActionOutcome {
        guard let preference = preference(key: key) else { return refuse("there is no such preference") }
        return await submit(PreferenceChange(key: key, expectedRevision: preference.revision))
    }

    /// Applies a refused change again to the preference's current revision, after the owner has seen the current
    /// value and chosen to keep the change.
    @discardableResult
    public func applyAgain(key: String) async -> ActionOutcome {
        guard let conflict = conflicts[key], let entryID = conflict.conflict.entryID else {
            return refuse("there is no refused change for this preference")
        }
        guard let revision = conflict.current?.revision ?? conflict.conflict.currentRevision else {
            return refuse("the preference's current version is unknown; reload the preferences and try again")
        }
        busyKeys.insert(key)
        defer { busyKeys.remove(key) }
        return await finish(key, await ActionSubmitter(context: context).resubmit(entryID, expectedRevision: revision))
    }

    /// Discards a refused change; the preference stays as the host has it. Returns whether it was discarded.
    @discardableResult
    public func discardChange(key: String) async -> Bool {
        guard let entryID = conflicts[key]?.conflict.entryID else { return false }
        let discarded = (try? await context.queue.discard(entryID)) != nil
        await syncQueue()
        return discarded
    }

    /// Dismisses the host's refusal shown for `key`, removing a refused change still held in the offline queue.
    /// Returns whether there was one.
    @discardableResult
    public func dismissIssue(key: String) async -> Bool {
        guard let issue = issues.removeValue(forKey: key) else { return false }
        if let entryID = issue.entryID {
            try? await context.queue.discard(entryID)
            await syncQueue()
        }
        return true
    }

    // MARK: - Internals

    private func submit(_ change: PreferenceChange) async -> ActionOutcome {
        busyKeys.insert(change.key)
        defer { busyKeys.remove(change.key) }
        issues[change.key] = nil
        let submission = await ActionSubmitter(context: context).submit(
            .updatePreferences(PreferencesPatchRequest(changes: [change])))
        if submission.outcome.isDone, change.value == nil, change.confirm != true { remove(change.key) }
        return await finish(change.key, submission)
    }

    /// Records a submission: the connectivity it showed, the preferences the host returned, the host's refusal for
    /// the key, and the queue's state; a conflict also reads the preferences again so the owner sees the current value.
    private func finish(_ key: String, _ submission: ActionSubmitter.Submission) async -> ActionOutcome {
        if let contact = submission.contact { await contacts?.record(contact) }
        if submission.contact == .revoked { hideDataIfRemoved(.revoked) }
        if let updated = submission.decoded([PreferenceDTO].self) { merge(updated) }
        switch submission.outcome {
        case .done:
            issues[key] = nil
        case .failed(let reason):
            let refusal = submission.entry?.lastError
            issues[key] = PreferenceIssue(key: key, message: refusal?.message ?? reason, status: refusal?.status)
        default:
            break
        }
        await syncQueue()
        if case .conflict = submission.outcome { await load() }
        lastOutcome = submission.outcome
        return submission.outcome
    }

    /// Reports a change refused before anything was sent.
    private func refuse(_ reason: String) -> ActionOutcome {
        let outcome = ActionOutcome.failed(reason: reason)
        lastOutcome = outcome
        return outcome
    }

    /// Stops showing the owner's preferences when the device is not paired or the host removed it.
    private func hideDataIfRemoved(_ failure: LoadFailure) {
        guard failure.hidesData else { return }
        generation += 1
        state = .failed(failure, previous: nil)
    }

    /// Shows the preferences the host returned after a change, replacing the shown ones with the same keys.
    private func merge(_ returned: [PreferenceDTO]) {
        state = state.updatingShown { shown in
            for preference in returned {
                if let index = shown.firstIndex(where: { $0.key == preference.key }) {
                    shown[index] = preference
                } else {
                    shown.append(preference)
                }
            }
            shown.sort { $0.key < $1.key }
        }
    }

    /// Stops showing a preference the host deleted.
    private func remove(_ key: String) {
        state = state.updatingShown { shown in shown.removeAll { $0.key == key } }
    }

    /// Reads the preference changes waiting in the queue, those refused as conflicts, and those the host refused when
    /// they were sent from the queue later.
    private func syncQueue() async {
        let queue = context.queue
        var pending: [String: PreferenceChange] = [:]
        for entry in await queue.pendingEntries where entry.kind == .preferenceChange {
            guard case .updatePreferences(let request)? = try? entry.mutation() else { continue }
            for change in request.changes { pending[change.key] = change }
        }
        var refused: [String: PreferenceConflict] = [:]
        for entry in await queue.conflictEntries where entry.kind == .preferenceChange {
            guard case .updatePreferences(let request)? = try? entry.mutation(),
                let conflict = ActionConflict(entry: entry)
            else { continue }
            for change in request.changes {
                refused[change.key] = PreferenceConflict(
                    key: change.key, conflict: conflict, change: change, current: preference(key: change.key))
            }
        }
        var refusals = issues.filter { $0.value.entryID == nil }
        for entry in await queue.failedEntries where entry.kind == .preferenceChange {
            guard case .updatePreferences(let request)? = try? entry.mutation() else { continue }
            let field = entry.lastError?.field
            guard let key = request.changes.first(where: { $0.key == field })?.key ?? request.changes.first?.key else {
                continue
            }
            refusals[key] = PreferenceIssue(
                key: key, message: entry.lastError?.message ?? "the host refused the change",
                status: entry.lastError?.status, entryID: entry.id)
        }
        pendingChanges = pending
        conflicts = refused
        issues = refusals
    }
}
