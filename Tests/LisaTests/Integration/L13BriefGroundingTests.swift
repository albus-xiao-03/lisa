// Integration tests for L13, brief grounding (BRIEF-01, BRIEF-02, BRIEF-03, PLAN-05, MODEL-04; D-18): a brief built
// from configured calendars, mail and a feed, with an owner task, an idea and a proposal, links every source-based
// item to a stored record (news also to its original address); a source that could not be checked, failing or stale,
// is named in both versions and kept apart from one checked with nothing new; the spoken version carries no
// addresses or internal identifiers.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("L13 — Brief grounding", .tags(.integration))
struct L13BriefGroundingTests {
    private let today = TestTime.date("2026-11-16")
    private let standup = SyntheticEvent(
        uid: "l13-standup@example.com", title: "Synthetic standup", start: "2026-11-16T09:00", end: "2026-11-16T09:30")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    private func feed(_ items: [(title: String, link: String)]) -> String {
        let entries = items.map { item in
            "<item><title>\(item.title)</title><link>\(item.link)</link><guid>\(item.link)</guid>"
                + "<pubDate>Mon, 16 Nov 2026 06:00:00 -0500</pubDate>"
                + "<description>A synthetic summary.</description></item>"
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Synthetic news</title><link>https://news.example.com/</link>
            <description>Synthetic</description>\(entries.joined())</channel></rss>
            """
    }

    /// Whether `reference` names a record that is stored now.
    private func resolves(_ reference: SourceReference, in host: LisaHost) throws -> Bool {
        let app = host.application
        let id = reference.recordID
        switch reference.recordKind {
        case "occurrence": return try app.record(CalendarOccurrence.self, id: OccurrenceID(id)) != nil
        case "plan": return try app.record(Plan.self, id: PlanID(id)) != nil
        case "email": return try app.record(EmailMessage.self, id: EmailID(id)) != nil
        case "evidence": return try app.record(Evidence.self, id: EvidenceID(id)) != nil
        case "idea": return try app.record(Idea.self, id: IdeaID(id)) != nil
        case "news": return try app.record(NewsItem.self, id: NewsID(id)) != nil
        case "proposal": return try app.record(EventProposal.self, id: ProposalID(id)) != nil
        case "source": return try app.record(Source.self, id: SourceID(id)) != nil
        case "task": return try app.record(LisaTask.self, id: TaskID(id)) != nil
        default: return false
        }
    }

    /// Whether `text` contains a web address or something shaped like a record identifier.
    private func hasAddressOrIdentifier(_ text: String) -> Bool {
        text.contains("://")
            || text.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}", options: .regularExpression) != nil
    }

    @Test("Every source-based item links to a stored record, and the spoken version has no addresses or identifiers")
    func itemsLinkToTheirEvidence() async throws {
        try await ScratchDirectory.with { scratch in
            let work = scratch.path("calendars", "work.ics")
            let home = scratch.path("calendars", "home.ics")
            let mailbox = scratch.path("mailbox")
            let news = scratch.path("feeds", "news.xml")
            try SourceFiles.write(SyntheticEvent.calendar([standup]), to: work, modifiedAt: at("06:00"))
            try SourceFiles.write("BEGIN:VCALENDAR\r\nnot a calendar\r\n", to: home, modifiedAt: at("06:00"))
            try SourceFiles.write(
                feed([("Synthetic markets update", "https://news.example.com/markets")]), to: news,
                modifiedAt: at("06:00"))
            try SourceFiles.write(
                SyntheticMail.message(
                    subject: "Budget", from: "Colleague <colleague@example.com>", to: TestHost.ownerAddress,
                    messageID: "<l13-1@example.com>", body: "Please send the synthetic budget by 2026-11-17.\n"),
                named: "m001", in: mailbox, receivedAt: at("06:00"))
            try SourceFiles.write(
                SyntheticInvitation.mail(
                    SyntheticEvent(
                        uid: "l13-lunch@example.com", title: "Synthetic partner lunch", start: "2026-11-17T12:00",
                        end: "2026-11-17T13:00"),
                    messageID: "<l13-2@example.com>"),
                named: "m002", in: mailbox, receivedAt: at("06:00"))
            var owner = TestHost.owner()
            owner.newsInterests = ["markets"]
            var testHost = TestHost(
                scratch: scratch, now: at("07:00"), owner: owner,
                sources: [
                    SourceFiles.calendarSource(work),
                    SourceFiles.calendarSource(home, key: "home", name: "Home calendar"),
                    SourceFiles.mailSource(mailbox), SourceFiles.feedSource(news),
                ])
            testHost.settings.model = .deterministic
            let host = try testHost.open()
            let app = host.application
            _ = try app.createTask(
                TaskDraft(title: "Synthetic tax filing", priority: .high, deadline: SyntheticTask.due(at("17:00"))),
                by: .localOwner)
            let idea = try #require(
                try app.capture(
                    CaptureRequest(kind: .idea, text: "Sketch a synthetic garden", channel: .commandLine),
                    by: .localOwner
                ).idea)
            _ = try app.moveIdea(idea.id, to: .availableForPlanning, expectedRevision: idea.revision, by: .localOwner)
            await host.runtime.runOnce()
            // The standup moves, which is a material change for the brief.
            try SourceFiles.write(
                SyntheticEvent.calendar([
                    SyntheticEvent(
                        uid: standup.uid, title: standup.title, start: "2026-11-16T09:15", end: "2026-11-16T09:45")
                ]), to: work, modifiedAt: at("07:03"))
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            await host.runtime.runOnce()

            let brief = try app.services.briefs.generate(for: today)
            let sections = Set(brief.items.map(\.section))
            for section in [
                BriefSection.commitments, .deadlines, .email, .events, .ideas, .news, .changes, .sourceHealth,
            ] {
                #expect(sections.contains(section), "the brief has no \(section) item: \(brief.text)")
            }
            for item in brief.items where item.section != .sourceHealth {
                #expect(!item.references.isEmpty, "\(item.section): \(item.text)")
            }
            for item in brief.items {
                for reference in item.references {
                    #expect(try resolves(reference, in: host), "\(reference.recordKind) \(reference.recordID)")
                }
            }
            let newsItem = try #require(brief.items.first { $0.section == .news })
            #expect(newsItem.references.first?.originalURL == "https://news.example.com/markets")
            // The failing calendar is named, and linked to its source record.
            let failing = try #require(brief.items.first { $0.text.hasPrefix("Could not check Home calendar") })
            #expect(failing.references.map(\.recordKind) == ["source"])
            // Both versions carry every material item; only the readable one may carry addresses.
            for item in brief.items where item.isMaterial {
                #expect(brief.text.contains(item.text), "missing from the text: \(item.text)")
                #expect(brief.spokenText.contains(item.spokenText), "missing from speech: \(item.spokenText)")
            }
            #expect(!hasAddressOrIdentifier(brief.spokenText), "\(brief.spokenText)")
            host.close()
        }
    }

    @Test("A failing or stale source is named as not checked, apart from a source checked with nothing new")
    func uncheckedSourcesAreNamed() async throws {
        try await ScratchDirectory.with { scratch in
            let work = scratch.path("calendars", "work.ics")
            let mailbox = try SourceFiles.directory(scratch.path("mailbox"))
            let shared = try SourceFiles.directory(scratch.path("shared"))
            let news = scratch.path("feeds", "news.xml")
            try SourceFiles.write(SyntheticEvent.calendar([standup]), to: work, modifiedAt: at("06:00"))
            try SourceFiles.write(feed([]), to: news, modifiedAt: at("06:00"))
            // The feed is refreshed only every two hours but is stale after ten minutes.
            var feedSource = SourceFiles.feedSource(news)
            feedSource.syncIntervalSeconds = 7_200
            feedSource.staleAfterSeconds = 600
            let testHost = TestHost(
                scratch: scratch, now: at("07:00"),
                sources: [
                    SourceFiles.calendarSource(work), SourceFiles.mailSource(mailbox),
                    SourceFiles.mailSource(shared, key: "shared", name: "Shared mailbox"), feedSource,
                ])
            let host = try testHost.open()
            await host.runtime.runOnce()
            // Every source was checked once at 07:00. Then the work calendar breaks and the shared mailbox goes away;
            // their next checks fail while their last successes are still recent.
            try SourceFiles.write("BEGIN:VCALENDAR\r\nbroken\r\n", to: work, modifiedAt: at("07:05"))
            try FileManager.default.removeItem(at: shared)
            testHost.advance(minutes: 30)
            await host.runtime.runOnce()

            let brief = try host.application.services.briefs.generate(for: today)
            #expect(brief.text.contains("Could not check Work calendar"))
            #expect(brief.text.contains("Could not check Synthetic news (not refreshed recently)"))
            #expect(brief.text.contains("Could not check Shared mailbox"))
            #expect(brief.text.contains("Checked, nothing new to report: Lisa's mailbox"))
            #expect(!brief.text.contains("Could not check Lisa's mailbox"))
            // A source whose latest check failed is never reported as checked with nothing new.
            let quiet = brief.items.first { $0.text.hasPrefix("Checked, nothing new to report") }?.text ?? ""
            #expect(!quiet.contains("Shared mailbox"), "\(quiet)")
            #expect(brief.spokenText.contains("I could not check Work calendar."))
            #expect(brief.spokenText.contains("I could not check Shared mailbox."))
            #expect(brief.spokenText.contains("I could not check Synthetic news."))
            #expect(brief.spokenText.contains("I checked Lisa's mailbox and found nothing new to report."))
            // The calendar that could not be checked also makes availability uncertain, in both versions.
            let uncertain = try #require(brief.items.first { $0.uncertainty != nil })
            #expect(brief.spokenText.contains(uncertain.spokenText))
            host.close()
        }
    }
}
