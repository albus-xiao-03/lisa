// Event proposals (EVENT-01): matching against the calendar, owner review actions and `.ics` export.

import Foundation
import LisaDomain
import LisaICalendar
import LisaLogging
import LisaMatching
import LisaPorts
import LisaTime

/// Proposal operations. Lisa never writes to the owner's calendar; the owner adds events and Lisa recognizes them.
public final class ProposalService: Sendable {
    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger
    private let settings: any SettingsSource

    public init(store: any RecordStore, clock: any WallClock, logger: Logger, settings: any SettingsSource) {
        self.store = store
        self.clock = clock
        self.logger = logger
        self.settings = settings
    }

    /// Re-matches unresolved proposals (and ones the owner reported as added) against current occurrences.
    @discardableResult
    public func rematch() throws -> [DomainChange] {
        let zone = try settings.currentSettings().zone.timeZone
        let now = clock.now()
        return try store.write { tx in
            var changes: [DomainChange] = []
            let open = try tx.find(EventProposal.self, .all).filter { proposal in
                if case .ownerReportsAdded = proposal.matchState { return true }
                return proposal.matchState.isUnresolved
            }
            for proposal in open {
                let candidates = try Self.candidates(for: proposal, zone: zone, in: tx)
                let state = EventMatcher.match(proposal, against: candidates, zone: zone)
                guard state != proposal.matchState else { continue }
                var updated = proposal
                updated.matchState = state
                updated.updatedAt = now
                try tx.update(updated)
                changes.append(.proposalChanged(proposal.id))
            }
            return changes
        }
    }

    /// Occurrences near the proposal's date (the day before through the day after).
    static func candidates(for proposal: EventProposal, zone: TimeZone, in tx: any RecordWriting) throws
        -> [CalendarOccurrence]
    {
        let day: LocalDate
        switch proposal.timing {
        case .timed(let start, _, _): day = ZoneRules.localDate(for: start, in: zone)
        case .dateOnly(let date): day = date
        case .unknown: return []
        }
        let from = ZoneRules.startOfDay(day.adding(days: -1), in: zone)
        let to = ZoneRules.startOfDay(day.adding(days: 2), in: zone)
        return try tx.find(
            CalendarOccurrence.self,
            RecordQuery.all.filter("start_at", .greaterOrEqual, .instant(from)).filter(
                "start_at", .lessThan, .instant(to)))
    }

    /// Applies an owner review action, checking the revision the owner saw.
    public func apply(_ action: ProposalAction, to id: ProposalID, expectedRevision: Revision, by principal: Principal)
        throws -> (EventProposal, DomainChange)
    {
        switch principal {
        case .localOwner, .pairedDevice, .demonstration: break
        case .runtime, .model: throw DomainError.notPermitted("proposals are reviewed only by the owner")
        }
        let now = clock.now()
        let saved = try store.write { tx -> EventProposal in
            var proposal = try tx.require(EventProposal.self, id: id)
            guard proposal.revision == expectedRevision else {
                throw StoreError.conflict(
                    collection: EventProposal.collectionName, id: id.rawValue, expected: expectedRevision,
                    actual: proposal.revision)
            }
            if case .confirmMatch(let occurrenceID) = action {
                _ = try tx.require(CalendarOccurrence.self, id: occurrenceID)
            }
            try proposal.apply(action, at: now)
            let stored = try tx.update(proposal)
            try tx.insert(
                AuditEvent(
                    action: "proposal.reviewed", actor: principal, at: now, affected: [id.rawValue],
                    outcome: .succeeded,
                    detail: "state=\(stored.matchState.name)"))
            return stored
        }
        return (saved, .proposalChanged(id))
    }

    /// An `.ics` file the owner can open to add the proposed event to their calendar.
    public func exportICS(_ id: ProposalID) throws -> String {
        let proposal = try store.read { try $0.require(EventProposal.self, id: id) }
        let start: ExportEvent.Start
        switch proposal.timing {
        case .timed(let begin, let end, _): start = .instant(begin, end: end)
        case .dateOnly(let date): start = .date(date, endExclusive: date.adding(days: 1))
        case .unknown:
            throw DomainError.invalidValue(
                field: "timing", reason: "the proposal has no date; correct it before exporting")
        }
        let notes = proposal.uncertainty.isEmpty ? nil : "Uncertain: " + proposal.uncertainty.joined(separator: "; ")
        return ICalendarWriter.write(
            [
                ExportEvent(
                    uid: "proposal-\(proposal.id.rawValue)@lisa", title: proposal.title, start: start,
                    location: proposal.location, notes: notes)
            ],
            stamp: clock.now())
    }
}
