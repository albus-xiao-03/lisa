// The rundown screen: today's or a chosen date's plan from the host, or the cached copy with its age while offline.

import Foundation
import LisaAPIContract
import LisaClient
import Observation

/// The rundown screen (UI-02): the plan for today or a chosen date.
///
/// While the host is unreachable the screen shows the cached rundown with its age, never as current (UI-03); when no
/// date is chosen, that may be an earlier day's rundown (`showsEarlierDay`). A device that is not paired, or that the
/// host removed, shows no rundown. Refreshing is explicit: nothing polls the host.
@MainActor
@Observable
public final class RundownModel {
    /// What the screen shows.
    public private(set) var state: LoadState<RundownDTO> = .idle
    /// The date shown (`YYYY-MM-DD`), or `nil` for the host's current date.
    public private(set) var date: String?

    @ObservationIgnored private let context: ClientContext
    @ObservationIgnored private let contacts: (any HostContactReporting)?
    @ObservationIgnored private var generation = 0

    /// A model that reads through `context` and reports connectivity to `contacts`.
    public init(context: ClientContext, contacts: (any HostContactReporting)? = nil) {
        self.context = context
        self.contacts = contacts
    }

    /// Loads the rundown of `date` (`YYYY-MM-DD`), or of the host's current date.
    public func load(date: String? = nil) async {
        if date != self.date { state = .idle }
        self.date = date
        await refresh()
    }

    /// Reads the shown date's rundown again. A refresh started later wins over an earlier one still running.
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
    }

    /// Whether the rundown shown is a cached copy of a day before this device's current date, shown because the host
    /// could not say which day is current.
    public var showsEarlierDay: Bool {
        guard date == nil, let result = state.result, result.source == .cache else { return false }
        return LocalDay.isBefore(result.value.date, dayOf: context.now(), in: context.timeZone)
    }
}
