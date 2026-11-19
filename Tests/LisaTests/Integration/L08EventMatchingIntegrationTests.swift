// Integration tests for L08, event matching at integration level (EVENT-01, CAL-01, CAL-02, MAIL-01, REM-01; D-20,
// D-32, D-33): proposals from invitations and from extraction are matched against stored calendar data in the review
// flow. Matched, possible match, not found, needs clarification, dismissed, and "owner reports added; awaiting
// refresh" stay distinct; owner decisions survive re-matching and a restart; an awaited event is matched once a
// refresh shows it; and only unresolved proposals keep follow-up reminders.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaTime
import Testing

@Suite("L08 — Event matching (integration)", .tags(.integration))
struct L08EventMatchingIntegrationTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    // In the subscribed calendar.
    private let budget = SyntheticEvent(
        uid: "l08-budget@example.com", title: "Synthetic budget review", start: "2026-11-18T14:00",
        end: "2026-11-18T15:00")
    private let designSync = SyntheticEvent(
        uid: "l08-design@example.com", title: "Synthetic design sync", start: "2026-11-18T16:00",
        end: "2026-11-18T17:00")
    // Added to the calendar later, after the owner reports adding it.
    private let offsite = SyntheticEvent(
        uid: "l08-offsite@example.com", title: "Synthetic offsite planning", start: "2026-11-19T09:00",
        end: "2026-11-19T10:00")

    /// Invitations: the same budget review (another UID), a design sync prep on the same day as the design sync, the
    /// offsite (not yet in the calendar) and a vendor call that never appears; plus a message naming a meeting with no
    /// date, which extraction turns into a proposal.
    private var mailbox: [(name: String, mail: SyntheticMail)] {
        [
            (
                "m001",
                SyntheticInvitation.mail(
                    SyntheticEvent(
                        uid: "l08-invite-budget@example.com", title: budget.title, start: budget.start,
                        end: budget.end),
                    messageID: "<l08-1@example.com>")
            ),
            (
                "m002",
                SyntheticInvitation.mail(
                    SyntheticEvent(
                        uid: "l08-invite-design@example.com", title: "Synthetic design sync prep",
                        start: "2026-11-18T10:00", end: "2026-11-18T10:30"),
                    messageID: "<l08-2@example.com>")
            ),
            ("m003", SyntheticInvitation.mail(offsite, messageID: "<l08-3@example.com>")),
            (
                "m004",
                SyntheticInvitation.mail(
                    SyntheticEvent(
                        uid: "l08-invite-vendor@example.com", title: "Synthetic vendor call",
                        start: "2026-11-19T11:00", end: "2026-11-19T11:30"),
                    messageID: "<l08-4@example.com>")
            ),
            (
                "m005",
                SyntheticMail.message(
                    subject: "Retro", from: "Colleague <colleague@example.com>", to: TestHost.ownerAddress,
                    messageID: "<l08-5@example.com>", body: "Meeting: Synthetic retro\n")
            ),
        ]
    }

    private func proposals(_ host: LisaHost) throws -> [String: EventProposal] {
        Dictionary(uniqueKeysWithValues: try host.application.all(EventProposal.self).map { ($0.title, $0) })
    }

    private func occurrence(_ event: SyntheticEvent, in host: LisaHost) throws -> OccurrenceID {
        try #require(try host.application.all(CalendarOccurrence.self).first { $0.uid == event.uid }).id
    }

    /// The titles of proposals that have a follow-up reminder still waiting.
    private func followedUp(_ host: LisaHost) throws -> Set<String> {
        let titles = Dictionary(
            uniqueKeysWithValues: try host.application.all(EventProposal.self).map { ($0.id, $0.title) })
        return Set(
            try host.application.all(Reminder.self).compactMap { reminder -> String? in
                guard case .proposal(let id) = reminder.subject, reminder.state == .scheduled else { return nil }
                return titles[id]
            })
    }

    @Test("Each match state stays distinct through review, owner decisions, a restart and a calendar refresh")
    func matchStatesThroughTheReviewFlow() async throws {
        try await ScratchDirectory.with { scratch in
            let calendar = scratch.path("calendars", "work.ics")
            let inbox = scratch.path("mailbox")
            try SourceFiles.write(SyntheticEvent.calendar([budget, designSync]), to: calendar, modifiedAt: start)
            for message in mailbox {
                try SourceFiles.write(
                    message.mail, named: message.name, in: inbox, receivedAt: start.addingTimeInterval(-3600))
            }
            var testHost = TestHost(
                scratch: scratch, now: start,
                sources: [SourceFiles.calendarSource(calendar), SourceFiles.mailSource(inbox)])
            testHost.settings.model = .deterministic
            var host = try testHost.open()
            await host.runtime.runOnce()

            var stored = try proposals(host)
            #expect(stored.count == 5)
            #expect(stored[budget.title]?.matchState == .matched(try occurrence(budget, in: host)))
            guard case .possibleMatch(let candidate, _) = stored["Synthetic design sync prep"]?.matchState else {
                Issue.record("the design sync prep is not a possible match: \(String(describing: stored))")
                return
            }
            #expect(candidate == (try occurrence(designSync, in: host)))
            #expect(stored[offsite.title]?.matchState == .notFound)
            #expect(stored["Synthetic vendor call"]?.matchState == .notFound)
            #expect(stored["Synthetic retro"]?.matchState.name == "needsClarification")
            #expect(
                try followedUp(host) == [
                    "Synthetic design sync prep", offsite.title, "Synthetic vendor call", "Synthetic retro",
                ])

            // The owner dismisses the vendor call and reports having added the offsite to the calendar.
            testHost.advance(minutes: 5)
            let vendor = try #require(stored["Synthetic vendor call"])
            _ = try host.application.reviewProposal(
                .dismiss, vendor.id, expectedRevision: vendor.revision, by: .localOwner)
            let reported = try #require(stored[offsite.title])
            _ = try host.application.reviewProposal(
                .reportAdded, reported.id, expectedRevision: reported.revision, by: .localOwner)
            _ = try await host.application.runCycle()
            stored = try proposals(host)
            #expect(stored["Synthetic vendor call"]?.matchState == .dismissed)
            #expect(stored[offsite.title]?.matchState == .ownerReportsAdded(at: testHost.clock.now()))
            #expect(try followedUp(host) == ["Synthetic design sync prep", "Synthetic retro"])

            try testHost.restart(&host)
            _ = try await host.application.runCycle()
            let reopened = try proposals(host)
            #expect(reopened.mapValues(\.matchState) == stored.mapValues(\.matchState))

            // The calendar refresh now shows the offsite: the awaited proposal becomes a match; the dismissal stays.
            try SourceFiles.write(
                SyntheticEvent.calendar([budget, designSync, offsite]), to: calendar, modifiedAt: testHost.clock.now())
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()
            stored = try proposals(host)
            #expect(stored[offsite.title]?.matchState == .matched(try occurrence(offsite, in: host)))
            #expect(stored["Synthetic vendor call"]?.matchState == .dismissed)

            // The owner confirms the possible match.
            let prep = try #require(stored["Synthetic design sync prep"])
            _ = try host.application.reviewProposal(
                .confirmMatch(candidate), prep.id, expectedRevision: prep.revision, by: .localOwner)
            stored = try proposals(host)
            #expect(stored["Synthetic design sync prep"]?.matchState == .matched(candidate))
            #expect(stored["Synthetic retro"]?.matchState.name == "needsClarification")
            #expect(try followedUp(host) == ["Synthetic retro"])
            host.close()
        }
    }
}
