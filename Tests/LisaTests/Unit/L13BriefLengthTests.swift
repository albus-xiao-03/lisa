// Unit tests for L13, brief length (BRIEF-04, with BRIEF-01 and BRIEF-02 parity; D-18): the readable brief's target
// length is configurable, in the configuration file and as the owner's preference, with a concise default of 220 words;
// when a day holds more than the target, every commitment, deadline and warning is kept in both versions and
// lower-priority items are dropped first; what is left out stays whole for the full view, and the readable brief says
// how much was left out; and the spoken duration is an estimate from the spoken text's words at the configured rate,
// exposed as a number of seconds and never stated in the brief as a playback time.

import Foundation
import LisaBriefComposer
import LisaConfig
import LisaDomain
import LisaOwnerData
import LisaTime
import Testing

@Suite("L13 — Brief length", .tags(.unit))
struct L13BriefLengthTests {
    private let zone = TestTime.newYork
    private let date = TestTime.date("2026-11-16")
    private let now = TestTime.instant("2026-11-16T06:30", in: TestTime.newYork)

    /// The number of synthetic news items in the busy day; each renders to the same number of words.
    private static let newsCount = 12

    /// The smallest configuration: everything else takes its default.
    private static func configuration(_ extra: String = "") -> String {
        """
        {
          version: 1,
          dataDirectory: "/var/lib/lisa-synthetic",
          timeZone: "America/New_York",
          \(extra)
        }
        """
    }

    // MARK: - A busy synthetic day

    private func commitment(_ title: String, _ start: String, _ end: String) -> CalendarOccurrence {
        let range = TestTime.range(start, end, on: "2026-11-16", in: zone)
        return CalendarOccurrence(
            sourceID: SourceID("synthetic-calendar"), uid: "\(start)@calendar.example.com",
            occurrenceKey: "2026-11-16T\(start)", title: title, location: nil,
            timing: .timed(start: range.start, end: range.end, zone: zone, floating: false), status: .confirmed,
            availability: .busy, sequence: 0, sourceLastModified: nil, warnings: [], evidenceID: nil, now: now)
    }

    /// A ranked feed item whose readable line has 14 words and whose spoken line has 10, whatever its number.
    private func newsItem(_ number: Int) -> BriefNews {
        let item = NewsItem(
            sourceID: SourceID("synthetic-feed"), originalURL: "https://news.example.com/transit-\(number)",
            title: "Synthetic transit story \(number) about rail planning", accessibleText: "A synthetic summary.",
            boundary: .feedSummary, publishedAt: now.addingTimeInterval(-Double(number) * 600), retrievedAt: now,
            dedupKey: "transit-\(number)", evidenceID: EvidenceID("synthetic-evidence-\(number)"))
        return BriefNews(item: item, reason: "Matches your interest in \"transit\"", sourceName: "Synthetic news")
    }

    /// A busy Monday. Material: four commitments, three confirmed deadlines (today, tomorrow as a date only, and one
    /// overdue), a change and a source that could not be checked. Optional: two possible tasks, a checked mailbox with
    /// nothing new and twelve ranked news items.
    private func busyDay(_ settings: BriefSettings = BriefSettings()) -> BriefInput {
        let commitments = [
            commitment("Synthetic team standup", "09:00", "09:15"),
            commitment("Synthetic design review", "11:00", "12:00"),
            commitment("Synthetic dentist appointment", "14:00", "15:00"),
            commitment("Synthetic school pickup", "16:30", "17:00"),
        ]
        let deadlines = [
            SyntheticTask.confirmed(
                "Submit the synthetic expense report",
                deadline: SyntheticTask.due(TestTime.instant("2026-11-16T17:00", in: zone)), createdAt: now),
            SyntheticTask.confirmed(
                "Renew the synthetic parking permit", deadline: .onDate(TestTime.date("2026-11-17")), createdAt: now),
            SyntheticTask.confirmed(
                "Return the synthetic library books",
                deadline: SyntheticTask.due(TestTime.instant("2026-11-15T17:00", in: zone)), createdAt: now),
        ]
        let possible = [
            SyntheticTask.unconfirmed("Call the synthetic plumber back", deadline: nil, createdAt: now),
            SyntheticTask.unconfirmed("Book the synthetic team dinner", deadline: nil, createdAt: now),
        ]
        let change = BriefChange(
            text: "Synthetic design review moved to 11:00 AM.",
            spokenText: "The synthetic design review moved to 11 AM.",
            references: [SourceReference(recordKind: "occurrence", recordID: commitments[1].id.rawValue)])
        let sources = [
            SourceStatusLine(
                sourceID: SourceID("synthetic-school-calendar"), name: "Synthetic school calendar", kind: .calendarFeed,
                checked: false, detail: "authentication failed"),
            SourceStatusLine(
                sourceID: SourceID("synthetic-mailbox"), name: "Lisa's mailbox", kind: .mailbox, checked: true,
                detail: nil),
        ]
        return BriefInput(
            date: date, zone: zone, now: now, commitments: commitments, tasks: deadlines, possibleTasks: possible,
            emails: [], proposals: [], ideaBlocks: [], news: (1...Self.newsCount).map(newsItem), changes: [change],
            sources: sources, availabilityUncertain: false, settings: settings)
    }

    /// `input` composed with a target of `targetWords` and a speaking rate of `wordsPerMinute`.
    private func compose(_ input: BriefInput, targetWords: Int, wordsPerMinute: Int = 150) -> ComposedBrief {
        var input = input
        input.settings.targetWords = targetWords
        input.settings.wordsPerMinute = wordsPerMinute
        return BriefComposer.compose(input)
    }

    /// Words as a reader counts them: runs of characters between white space.
    private func words(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The words of the items' readable lines, which the target length bounds.
    private func itemWords(_ items: [BriefItem]) -> Int {
        items.reduce(0) { $0 + words($1.text) }
    }

    /// The brief's items that cite `recordID`.
    private func items(citing recordID: String, in items: [BriefItem]) -> [BriefItem] {
        items.filter { item in item.references.contains { $0.recordID == recordID } }
    }

    /// The issues of a configuration that must be refused.
    private func issues(_ text: String) -> [ConfigurationIssue] {
        do {
            _ = try ConfigurationLoader.parse(
                text: text, sourceName: "synthetic.json5", homeDirectory: "/home/synthetic")
            Issue.record("the configuration was accepted")
        } catch .invalid(let issues) {
            return issues
        } catch {
            Issue.record("the configuration was refused without listing its issues: \(error)")
        }
        return []
    }

    // MARK: - Tests

    @Test("The length defaults to a concise 220-word target at 150 words a minute, and a busy day is cut to it")
    func conciseDefault() throws {
        let defaults = BriefSettings()
        #expect(defaults.targetWords == 220)
        #expect(defaults.wordsPerMinute == 150)
        let configuration = try ConfigurationLoader.parse(
            text: Self.configuration(), sourceName: "synthetic.json5", homeDirectory: "/home/synthetic")
        #expect(configuration.brief.targetWords == 220)
        #expect(configuration.brief.wordsPerMinute == 150)
        #expect(configuration.ownerSettings().brief == defaults)

        // The busy day holds more than the default target; composed with the default, its items fit the target and the
        // rest is left out.
        let day = busyDay()
        let everything = compose(day, targetWords: 3000)
        #expect(everything.omitted.isEmpty)
        #expect(itemWords(everything.items) > defaults.targetWords)
        let brief = BriefComposer.compose(day)
        #expect(itemWords(brief.items) <= defaults.targetWords)
        #expect(!brief.omitted.isEmpty)
        #expect(brief.items.count + brief.omitted.count == everything.items.count)
    }

    @Test("The target is configurable in the configuration and as the owner's preference, from 50 to 3,000 words")
    func targetIsConfigurable() throws {
        let configured = try ConfigurationLoader.parse(
            text: Self.configuration("brief: { targetWords: 120, wordsPerMinute: 180 },"),
            sourceName: "synthetic.json5", homeDirectory: "/home/synthetic")
        #expect(configured.brief.targetWords == 120)
        #expect(configured.brief.wordsPerMinute == 180)
        #expect(configured.ownerSettings().brief.targetWords == 120)

        // Values outside the bounds are refused at the setting's line and column, with the bounds in the message.
        let refusals: [(setting: String, value: Int, bounds: String)] = [
            ("targetWords", 49, "between 50 and 3000"), ("targetWords", 3001, "between 50 and 3000"),
            ("wordsPerMinute", 59, "between 60 and 400"), ("wordsPerMinute", 401, "between 60 and 400"),
        ]
        for refusal in refusals {
            let found = issues(Self.configuration("brief: { \(refusal.setting): \(refusal.value) },"))
            #expect(found.count == 1)
            let issue = try #require(found.first)
            #expect(issue.path == "brief.\(refusal.setting)")
            #expect(issue.problem.contains(refusal.bounds))
            // Line 5 is `  brief: { <setting>: <value> },`: the setting starts in column 12 and its value two columns
            // after the setting's name ends.
            #expect(issue.line == 5)
            #expect(issue.column == 14 + refusal.setting.count)
        }

        // The owner's stored preference sets the same length, within the same bounds.
        var settings = OwnerSettings(zone: zone)
        try PreferenceMapping.apply(.briefLength, .number(120), to: &settings)
        #expect(settings.brief.targetWords == 120)
        for refused in [49, 3001, 120.5] {
            var copy = settings
            #expect(throws: DomainError.self) { try PreferenceMapping.apply(.briefLength, .number(refused), to: &copy) }
            #expect(copy.brief.targetWords == 120)
        }

        // A longer target keeps at least as much of the same day, and the longest keeps all of it.
        let day = busyDay()
        var kept = 0
        for target in [50, 100, 150, 220, 400, 3000] {
            let brief = compose(day, targetWords: target)
            #expect(brief.items.count >= kept)
            kept = brief.items.count
        }
        #expect(compose(day, targetWords: 3000).omitted.isEmpty)
        #expect(compose(day, targetWords: 120).items.count < compose(day, targetWords: 220).items.count)
    }

    @Test("Over the target, every commitment, deadline and warning stays in both versions; lower priorities go first")
    func commitmentsAndDeadlinesComeFirst() throws {
        let day = busyDay()
        let everything = compose(day, targetWords: 3000)
        let material = everything.items.filter(\.isMaterial)
        let news = everything.items.filter { $0.section == .news }
        #expect(news.count == Self.newsCount)

        // A target smaller than the material alone keeps all of it, and nothing else.
        let tight = compose(day, targetWords: 50)
        #expect(itemWords(material) > 50)
        #expect(tight.items == material)
        #expect(tight.omitted.count == everything.items.count - material.count)
        for record in day.commitments.map(\.id.rawValue) + day.tasks.map(\.id.rawValue) {
            let cited = items(citing: record, in: tight.items)
            #expect(cited.count >= 1)
            for item in cited {
                #expect(tight.text.contains(item.text))
                #expect(tight.spokenText.contains(item.spokenText))
            }
        }
        #expect(tight.text.contains("Could not check Synthetic school calendar"))
        #expect(tight.spokenText.contains("I could not check Synthetic school calendar."))

        // At every target, everything material is kept in both versions and only optional items are left out. The
        // optional items are dropped lowest priority first: news in rank order, and news only once the possible tasks
        // and the quiet-mailbox line are in.
        let higher = everything.items.filter { !$0.isMaterial && $0.section != .news }
        #expect(higher.count == 3)
        for target in stride(from: 50, through: 400, by: 5) {
            let brief = compose(day, targetWords: target)
            #expect(Set(material).isSubset(of: Set(brief.items)))
            #expect(brief.omitted.allSatisfy { !$0.isMaterial })
            #expect(BriefComposer.hasParity(brief))
            let keptNews = brief.items.filter { $0.section == .news }
            #expect(keptNews == Array(news.prefix(keptNews.count)))
            if !keptNews.isEmpty {
                #expect(Set(higher).isSubset(of: Set(brief.items)))
            }
        }
    }

    @Test("Items left out stay whole for the full view, and the readable brief says how many there are")
    func omittedItemsStayAvailable() {
        let day = busyDay()
        let everything = compose(day, targetWords: 3000)
        #expect(everything.omitted.isEmpty)
        #expect(!everything.text.contains("available in the full view"))

        // With the default target, what is left out is exactly what the brief no longer shows: nothing is lost, nothing
        // is changed (each item keeps its text, spoken text and references), and nothing is shown twice.
        let brief = BriefComposer.compose(day)
        #expect(!brief.omitted.isEmpty)
        #expect(brief.items.count + brief.omitted.count == everything.items.count)
        #expect(Set(brief.items).union(brief.omitted) == Set(everything.items))
        #expect(Set(brief.items).isDisjoint(with: brief.omitted))
        for item in brief.omitted {
            #expect(!brief.text.contains(item.text))
            #expect(!brief.spokenText.contains(item.spokenText))
        }
        #expect(brief.text.hasSuffix("\(brief.omitted.count) lower-priority items are available in the full view."))

        // One item left out is counted in the singular.
        let one = compose(day, targetWords: itemWords(everything.items) - 1)
        #expect(one.omitted.count == 1)
        #expect(one.text.hasSuffix("1 lower-priority item is available in the full view."))
    }

    @Test("The spoken duration is estimated from the spoken text's words at the set rate, never stated as a time")
    func spokenDurationIsAnEstimate() {
        let day = busyDay()
        for rate in [150, 100, 300] {
            for target in [3000, 220, 50] {
                let brief = compose(day, targetWords: target, wordsPerMinute: rate)
                let estimate = Int((Double(words(brief.spokenText)) / Double(rate) * 60).rounded())
                #expect(brief.estimatedSpokenSeconds == estimate)
            }
        }
        // The estimate follows the spoken version, whose word count differs from the readable one's, and a brief cut
        // to its target is estimated from what it still says.
        let everything = compose(day, targetWords: 3000)
        #expect(words(everything.spokenText) != words(everything.text))
        let short = compose(day, targetWords: 220)
        #expect(short.estimatedSpokenSeconds < everything.estimatedSpokenSeconds)
        // A faster speaking rate gives a shorter estimate for the same text.
        let fast = compose(day, targetWords: 3000, wordsPerMinute: 300)
        let slow = compose(day, targetWords: 3000, wordsPerMinute: 100)
        #expect(fast.estimatedSpokenSeconds < slow.estimatedSpokenSeconds)
        // Neither version states how long it takes to play; the estimate is only the separate number of seconds.
        for text in [everything.text, everything.spokenText, short.text, short.spokenText] {
            #expect(!text.lowercased().contains("second"))
            #expect(!text.lowercased().contains("minute"))
        }
    }
}
