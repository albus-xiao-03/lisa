// The brief screen and "read the brief": the host's brief or the cached copy with its age, plain spoken text,
// regeneration and its status, and stepping back to earlier days' briefs.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The brief screen (UI-02) and the source of what Siri and the app speak (SIRI-01, SIRI-02).
///
/// While the host is unreachable the screen shows the cached brief with its age, never as current (UI-03).
/// `spokenText` is the brief as plain sentences without markup; `speechText(at:)` adds a spoken notice when the brief
/// is a saved copy, so a stale brief is never read out as current. Regeneration is a direct request to the host: it
/// cannot be queued, so it is unavailable while the host cannot be reached. Earlier days' briefs are read one day at a
/// time with `load(date:)`, using `previousDate` and `nextDate` (UI-01: current and previous briefs).
@MainActor
@Observable
public final class BriefModel {
    /// What the screen shows.
    public private(set) var state: LoadState<BriefDTO> = .idle
    /// The date shown (`YYYY-MM-DD`), or `nil` for the host's current date.
    public private(set) var date: String?
    /// Whether a regeneration request is in flight.
    public private(set) var isRegenerating = false
    /// The outcome of the latest regeneration request.
    public private(set) var lastRegeneration: ActionOutcome?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// A model that reads through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    /// Loads the brief of `date` (`YYYY-MM-DD`), or of the host's current date.
    public func load(date: String? = nil) async {
        if date != self.date { state = .idle }
        self.date = date
        await refresh()
    }

    /// Reads the shown date's brief again. A refresh started later wins over an earlier one still running.
    public func refresh() async {
        generation += 1
        let current = generation
        let previous = state.result
        state = .loading(previous: previous)
        let reader = context.reader
        let date = date
        let next = await ReadRunner.load(previous: previous, contacts: contacts) {
            () async throws(ClientError) -> ReadResult<BriefDTO> in
            try await reader.brief(date: date)
        }
        guard current == generation else { return }
        state = next
    }

    /// Asks the host to regenerate the shown date's brief (`POST /v1/briefs/regenerate`). A failed regeneration keeps
    /// the last good brief, which the host returns with the failure; the outcome is then `.failed`.
    @discardableResult
    public func regenerate() async -> ActionOutcome {
        guard !isRegenerating else { return .failed(reason: "a regeneration is already in progress") }
        isRegenerating = true
        defer { isRegenerating = false }
        let outcome: ActionOutcome
        do throws(ClientError) {
            let brief = try await context.client.regenerateBrief(date: date)
            let fetchedAt = context.now()
            _ = try? await context.cache.store(brief, fetchedAt: fetchedAt)
            await contacts?.record(.reached)
            generation += 1
            state = .loaded(ReadResult(value: brief, fetchedAt: fetchedAt, source: .host))
            outcome =
                brief.state == "failed"
                ? .failed(
                    reason: brief.lastFailure ?? "the brief could not be regenerated; the last good brief is kept")
                : .done
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            if LoadFailure(error).hidesData {
                generation += 1
                state = .failed(LoadFailure(error), previous: nil)
            }
            outcome = ActionOutcome(unqueuedFailure: error)
        }
        lastRegeneration = outcome
        return outcome
    }

    /// The brief shown as plain sentences for speech, without markup, or `nil` when no brief is shown.
    public var spokenText: String? {
        guard let brief = state.value else { return nil }
        let text = SpokenText.plain(brief.spokenText.isEmpty ? brief.text : brief.spokenText)
        return text.isEmpty ? nil : text
    }

    /// What to say for "read the brief" at `now`: the spoken text, preceded by a notice when the brief is a saved copy
    /// rather than the host's current answer. `nil` when no brief is shown; `state.failure` then says why (for example
    /// `.notFound` when no brief is available yet).
    public func speechText(at now: Date) -> String? {
        guard let result = state.result, let spoken = spokenText else { return nil }
        guard state.isStale || showsEarlierDay else { return spoken }
        let day = LocalDay.spokenEnglish(result.value.date)
        return "This is the saved brief for \(day), from \(AgePhrase.english(result.age(at: now))) ago. It may be out "
            + "of date. " + spoken
    }

    /// The day before the brief shown (`YYYY-MM-DD`), to read earlier briefs one day at a time with `load(date:)`;
    /// `nil` while neither a date nor a brief is shown.
    public var previousDate: String? {
        guard let shown = date ?? state.value?.date else { return nil }
        return LocalDay.adding(-1, to: shown)
    }

    /// The day after the one shown while an earlier day was chosen, to step forward again; `nil` while the host's
    /// current brief is shown, which `load(date: nil)` returns to.
    public var nextDate: String? {
        date.flatMap { LocalDay.adding(1, to: $0) }
    }

    /// Where the brief shown stands, in words for the screen: being regenerated, kept after a failed regeneration,
    /// possibly out of date, or composed from templates without a model; `nil` when there is nothing to say.
    public var statusMessage: String? {
        if isRegenerating { return "Lisa is preparing a new version of this brief." }
        guard let brief = state.value else { return nil }
        switch brief.state {
        case "failed":
            let reason = brief.lastFailure.map { ": \($0)" } ?? ""
            return "The last attempt to prepare this brief failed\(reason). This is the last good version."
        case "stale":
            return "This brief may be out of date. Regenerate it to include the latest changes."
        default:
            return brief.templateOnly ? "Composed from templates; no language model was used." : nil
        }
    }

    /// Whether the brief shown is a cached copy of a day before this device's current date, shown because the host
    /// could not say which day is current.
    public var showsEarlierDay: Bool {
        guard date == nil, let result = state.result, result.source == .cache else { return false }
        return LocalDay.isBefore(result.value.date, dayOf: context.now(), in: context.timeZone)
    }
}
