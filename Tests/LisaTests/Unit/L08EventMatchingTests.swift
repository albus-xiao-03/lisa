// Unit tests for L08, event matching at engine level (EVENT-01; D-20): exact match by UID or by a strong title and
// start, possible match, no match, dismissal, an owner-reported addition awaiting refresh, and a proposal without a
// date, which needs details. Each state behaves distinctly.

import Foundation
import LisaDomain
import LisaMatching
import LisaTime
import Testing

@Suite("L08 — Event matching", .tags(.unit))
struct L08EventMatchingTests {
    private let zone = TestTime.newYork
    private let now = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    private func occurrence(
        _ uid: String, _ title: String, at start: String, minutes: Int = 60, status: OccurrenceStatus = .confirmed
    ) -> CalendarOccurrence {
        let begin = TestTime.instant(start, in: zone)
        return CalendarOccurrence(
            id: OccurrenceID("occurrence-\(uid)"), sourceID: SourceID("calendar-source-1"), uid: uid,
            occurrenceKey: "single", title: title, location: nil,
            timing: .timed(
                start: begin, end: begin.addingTimeInterval(TimeInterval(minutes * 60)), zone: zone, floating: false),
            status: status, availability: .busy, sequence: 0, sourceLastModified: nil, warnings: [], evidenceID: nil,
            now: now)
    }

    private func proposal(_ title: String, at start: String?) -> EventProposal {
        let timing: ProposedTiming =
            start.map { .timed(start: TestTime.instant($0, in: zone), end: nil, zone: zone) } ?? .unknown
        return EventProposal(title: title, timing: timing, evidenceIDs: [EvidenceID("evidence-1")], now: now)
    }

    private func match(_ proposal: EventProposal, _ occurrences: [CalendarOccurrence], uid: String? = nil)
        -> ProposalMatchState
    {
        EventMatcher.match(proposal, against: occurrences, zone: zone.timeZone, proposalUID: uid)
    }

    @Test("The same iCalendar UID is an exact match, whatever the title; a cancelled occurrence never matches")
    func sameUIDMatches() {
        let event = occurrence("invite-7@example.com", "Design review", at: "2026-11-18T14:00")
        let unrelated = proposal("Something else entirely", at: "2026-11-20T09:00")
        #expect(match(unrelated, [event], uid: "invite-7@example.com") == .matched(event.id))

        let cancelled = occurrence("invite-7@example.com", "Design review", at: "2026-11-18T14:00", status: .cancelled)
        #expect(match(unrelated, [cancelled], uid: "invite-7@example.com") == .notFound)
    }

    @Test("A strong title match starting within five minutes is a match; six minutes apart is only possible")
    func strongTitleAndStart() {
        let candidate = proposal("Budget review with Dana", at: "2026-11-16T14:00")
        let within = occurrence("budget-1", "Budget Review — Dana", at: "2026-11-16T14:05")
        #expect(match(candidate, [within]) == .matched(within.id))

        let apart = occurrence("budget-2", "Budget Review — Dana", at: "2026-11-16T14:06")
        guard case .possibleMatch(let id, let reasons) = match(candidate, [apart]) else {
            Issue.record("six minutes apart must not be a match")
            return
        }
        #expect(id == apart.id)
        #expect(reasons.contains("same day"))
    }

    @Test("A partial title match on the same day is a possible match, with its reasons")
    func partialTitleSameDayIsPossible() {
        let candidate = proposal("Dentist appointment", at: "2026-11-16T10:00")
        let event = occurrence("dentist-1", "Dentist", at: "2026-11-16T15:00")
        #expect(match(candidate, [event]) == .possibleMatch(event.id, reasons: ["title similarity 50%", "same day"]))
    }

    @Test("The same start with a weak title match is a possible match")
    func sameStartWeakTitleIsPossible() {
        let candidate = proposal("Design review", at: "2026-11-16T14:00")
        let event = occurrence("design-1", "Design sync", at: "2026-11-16T14:00")
        #expect(
            match(candidate, [event]) == .possibleMatch(event.id, reasons: ["title similarity 33%", "same start time"]))
    }

    @Test("A loose similarity is never proof: half the title words at the same start stays possible")
    func looseSimilarityIsNotProof() {
        let candidate = proposal("Dentist appointment", at: "2026-11-16T14:00")
        let event = occurrence("dentist-2", "Dentist", at: "2026-11-16T14:00")
        guard case .possibleMatch(let id, _) = match(candidate, [event]) else {
            Issue.record("a 50% title similarity must not count as a match")
            return
        }
        #expect(id == event.id)
    }

    @Test("Without a comparable occurrence the proposal is not found")
    func noComparableOccurrence() {
        let candidate = proposal("Design review", at: "2026-11-16T14:00")
        #expect(match(candidate, []) == .notFound)
        #expect(match(candidate, [occurrence("lunch-1", "Lunch with Sam", at: "2026-11-16T14:00")]) == .notFound)
        #expect(match(candidate, [occurrence("design-2", "Design review", at: "2026-11-17T14:00")]) == .notFound)
        #expect(
            match(candidate, [occurrence("design-3", "Design review", at: "2026-11-16T14:00", status: .cancelled)])
                == .notFound)
    }

    @Test("The best candidate wins, whatever the order of the occurrences")
    func bestCandidateIsOrderIndependent() {
        let candidate = proposal("Project kickoff", at: "2026-11-16T14:00")
        let later = occurrence("kickoff-later", "Project kickoff", at: "2026-11-16T16:00")
        let exact = occurrence("kickoff-exact", "Project kickoff", at: "2026-11-16T14:00")
        #expect(match(candidate, [later, exact]) == .matched(exact.id))
        #expect(match(candidate, [exact, later]) == .matched(exact.id))
    }

    @Test("A dismissed proposal stays dismissed, and a dismissal cannot become a match or a report")
    func dismissalIsKept() throws {
        let event = occurrence("budget-1", "Budget review", at: "2026-11-16T14:00")
        var candidate = proposal("Budget review", at: "2026-11-16T14:00")
        try candidate.apply(.dismiss, at: now)
        #expect(candidate.matchState == .dismissed)
        #expect(match(candidate, [event]) == .dismissed)
        #expect(throws: DomainError.self) { try candidate.apply(.confirmMatch(event.id), at: now) }
        #expect(throws: DomainError.self) { try candidate.apply(.reportAdded, at: now) }
        #expect(candidate.matchState == .dismissed)
    }

    @Test("A match the owner confirmed is kept even when the calendars no longer show it")
    func confirmedMatchIsKept() throws {
        let event = occurrence("budget-1", "Budget review", at: "2026-11-16T14:00")
        var candidate = proposal("Something the owner recognised", at: "2026-11-16T09:00")
        try candidate.apply(.confirmMatch(event.id), at: now)
        #expect(match(candidate, []) == .matched(event.id))
    }

    @Test("Owner reports added: the proposal awaits refresh until a matching occurrence appears")
    func awaitingRefresh() throws {
        var candidate = proposal("Budget review", at: "2026-11-16T14:00")
        let reportedAt = TestTime.instant("2026-11-16T08:30", in: TestTime.newYork)
        try candidate.apply(.reportAdded, at: reportedAt)
        #expect(candidate.matchState == .ownerReportsAdded(at: reportedAt))
        #expect(!candidate.matchState.isUnresolved)
        #expect(match(candidate, []) == .ownerReportsAdded(at: reportedAt))
        #expect(
            match(candidate, [occurrence("lunch-1", "Lunch", at: "2026-11-16T12:00")])
                == .ownerReportsAdded(at: reportedAt))
        let arrived = occurrence("budget-1", "Budget review", at: "2026-11-16T14:00")
        #expect(match(candidate, [arrived]) == .matched(arrived.id))
    }

    @Test("A proposal without a date needs clarification until the owner supplies one")
    func proposalWithoutDateNeedsDetails() throws {
        let event = occurrence("budget-1", "Budget review", at: "2026-11-16T14:00")
        var candidate = proposal("Budget review", at: nil)
        #expect(candidate.matchState == .needsClarification("the date or time is missing"))
        #expect(match(candidate, [event]) == .needsClarification("the date or time is missing"))
        #expect(match(candidate, []) == .needsClarification("the date or time is missing"))

        try candidate.apply(.correct(title: "Budget Review", timing: nil, location: nil), at: now)
        #expect(candidate.matchState == .needsClarification("the date or time is missing"))

        let start = TestTime.instant("2026-11-16T14:00", in: TestTime.newYork)
        try candidate.apply(
            .correct(title: nil, timing: .timed(start: start, end: nil, zone: zone), location: nil), at: now)
        #expect(candidate.matchState == .notFound)
        #expect(candidate.ownerCorrected == [.title, .timing])
        #expect(match(candidate, [event]) == .matched(event.id))
    }

    @Test("A date-only proposal can at most be a possible match: there is no time to compare")
    func dateOnlyProposalIsAtMostPossible() {
        let candidate = EventProposal(
            title: "Team offsite", timing: .dateOnly(TestTime.date("2026-11-16")), evidenceIDs: [EvidenceID("e-2")],
            now: now)
        let event = occurrence("offsite-1", "Team offsite", at: "2026-11-16T09:00")
        guard case .possibleMatch(let id, let reasons) = match(candidate, [event]) else {
            Issue.record("a date-only proposal must not be matched on its title alone")
            return
        }
        #expect(id == event.id)
        #expect(reasons.contains("same day"))
    }

    @Test("The six states are distinct, and only clarification, not-found and possible need the owner")
    func statesAreDistinct() {
        let occurrenceID = OccurrenceID("occurrence-x")
        let states: [ProposalMatchState] = [
            .needsClarification("missing"), .notFound, .possibleMatch(occurrenceID, reasons: []),
            .matched(occurrenceID), .dismissed, .ownerReportsAdded(at: now),
        ]
        #expect(Set(states.map(\.name)).count == 6)
        #expect(states.map(\.isUnresolved) == [true, true, true, false, false, false])
    }
}
