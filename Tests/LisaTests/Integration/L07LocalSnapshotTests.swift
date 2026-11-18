// Integration tests for L07, incomplete refresh, with local snapshot sources (CAL-02, INGEST-01, NEWS-01, OPS-02;
// D-32, D-37): a calendar or feed directory is read as one complete snapshot, so a file in it over the size limit
// fails the whole refresh as partial and nothing any file held is cancelled or removed until a complete refresh
// succeeds; a configured single file that is missing fails the refresh with class `configuration` and keeps what it
// held; and a mail directory, which is read incrementally, skips an oversized message with a visible note and reads
// every other message once.

import Foundation
import LisaDomain
import LisaHost
import LisaLocalSources
import LisaPorts
import Testing

@Suite("L07 — Local snapshot sources", .tags(.integration))
struct L07LocalSnapshotTests {
    /// Every file above this size is over the limit of one pass.
    private static let maxBytes = 4_000
    private let work = SyntheticEvent(
        uid: "l07-local-work@example.com", title: "Synthetic work review", start: "2026-11-16T10:00",
        end: "2026-11-16T11:00")
    private let home = SyntheticEvent(
        uid: "l07-local-home@example.com", title: "Synthetic home visit", start: "2026-11-16T15:00",
        end: "2026-11-16T16:00")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    private func testHost(_ scratch: ScratchDirectory, sources: [HostSource]) -> TestHost {
        var testHost = TestHost(scratch: scratch, now: at("07:00"), sources: sources)
        testHost.settings.syncLimits = SyncLimits(maxItems: 50, maxBytes: Self.maxBytes)
        return testHost
    }

    private func source(_ key: String, in host: LisaHost) throws -> Source {
        try #require(try host.application.all(Source.self).first { $0.configurationKey == key })
    }

    private func cycle(_ host: LisaHost, _ testHost: TestHost) async {
        testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
        await host.runtime.runOnce()
    }

    /// An X- property long enough to put a file over the limit; the connector refuses the file by its size alone.
    private static let padding = "X-LISA-TEST-PADDING:" + String(repeating: "p", count: maxBytes)

    /// An RSS document with one item per title, each with a stable guid, optionally padded past the limit.
    private static func feed(_ titles: [String], padded: Bool = false) -> String {
        let items = titles.map { title in
            "<item><title>\(title)</title><guid>l07-\(title.lowercased().filter(\.isLetter))</guid>"
                + "<link>https://news.example.com/\(title.lowercased().filter(\.isLetter))</link>"
                + "<pubDate>Mon, 16 Nov 2026 06:00:00 -0500</pubDate></item>"
        }
        let description = padded ? String(repeating: "Synthetic padding. ", count: maxBytes / 10) : "Synthetic"
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Synthetic local news</title><link>https://news.example.com/</link>
            <description>\(description)</description>\(items.joined())</channel></rss>
            """
    }

    @Test(
        "A calendar file over the size limit fails the snapshot as partial, and no event of the directory is cancelled")
    func oversizedCalendarFileCancelsNothing() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("calendars")
            let workFile = directory.appendingPathComponent("work.ics")
            let homeFile = directory.appendingPathComponent("home.ics")
            try SourceFiles.write(SyntheticEvent.calendar([work]), to: workFile, modifiedAt: at("06:00"))
            try SourceFiles.write(SyntheticEvent.calendar([home]), to: homeFile, modifiedAt: at("06:00"))
            let calendars = HostSource(
                key: "calendars", name: "Local calendars", kind: .calendarFeed, syncIntervalSeconds: 300,
                access: .localDirectory(directory, .calendar))
            let testHost = testHost(scratch, sources: [calendars])
            let host = try testHost.open()
            await host.runtime.runOnce()
            let before = try host.application.all(CalendarOccurrence.self)
            #expect(Set(before.filter(\.blocksTime).map(\.uid)) == [work.uid, home.uid])

            // The work event is gone, and the home calendar grew over the limit while keeping its event.
            try SourceFiles.write(SyntheticEvent.calendar([]), to: workFile, modifiedAt: at("07:02"))
            var padded = home
            padded.properties = [Self.padding]
            try SourceFiles.write(SyntheticEvent.calendar([padded]), to: homeFile, modifiedAt: at("07:02"))
            await cycle(host, testHost)
            let failing = try source("calendars", in: host)
            #expect(failing.isFailing)
            #expect(failing.lastFailure?.errorClass == .partial)
            #expect(failing.lastFailure?.summary.contains("home.ics") == true)
            let kept = try host.application.all(CalendarOccurrence.self)
            #expect(Set(kept.filter(\.blocksTime).map(\.uid)) == [work.uid, home.uid])
            for occurrence in before {
                #expect(kept.first { $0.id == occurrence.id }?.revision == occurrence.revision)
            }

            // Once the directory can be read whole again, the complete refresh removes the work event only.
            try SourceFiles.write(SyntheticEvent.calendar([home]), to: homeFile, modifiedAt: at("07:10"))
            await cycle(host, testHost)
            #expect(!(try source("calendars", in: host)).isFailing)
            let after = try host.application.all(CalendarOccurrence.self)
            #expect(after.filter(\.blocksTime).map(\.uid) == [home.uid])
            #expect(after.first { $0.uid == work.uid }?.status == .cancelled)
            host.close()
        }
    }

    @Test("A feed file over the size limit fails the snapshot as partial, and every stored item stays")
    func oversizedFeedFileRemovesNothing() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("feeds")
            let first = directory.appendingPathComponent("first.xml")
            let second = directory.appendingPathComponent("second.xml")
            try SourceFiles.write(Self.feed(["Alpha"]), to: first, modifiedAt: at("06:00"))
            try SourceFiles.write(Self.feed(["Bravo"]), to: second, modifiedAt: at("06:00"))
            let feeds = HostSource(
                key: "feeds", name: "Local feeds", kind: .newsFeed, syncIntervalSeconds: 300,
                access: .localDirectory(directory, .feed))
            let testHost = testHost(scratch, sources: [feeds])
            let host = try testHost.open()
            await host.runtime.runOnce()
            #expect(Set(try host.application.all(NewsItem.self).map(\.title)) == ["Alpha", "Bravo"])

            try SourceFiles.write(Self.feed(["Bravo", "Charlie"], padded: true), to: second, modifiedAt: at("07:02"))
            await cycle(host, testHost)
            let failing = try source("feeds", in: host)
            #expect(failing.isFailing)
            #expect(failing.lastFailure?.errorClass == .partial)
            // Nothing was taken from the incomplete snapshot, and nothing stored was removed.
            #expect(Set(try host.application.all(NewsItem.self).map(\.title)) == ["Alpha", "Bravo"])

            try SourceFiles.write(Self.feed(["Bravo", "Charlie"]), to: second, modifiedAt: at("07:10"))
            await cycle(host, testHost)
            #expect(!(try source("feeds", in: host)).isFailing)
            #expect(Set(try host.application.all(NewsItem.self).map(\.title)) == ["Alpha", "Bravo", "Charlie"])
            host.close()
        }
    }

    @Test(
        "A configured single file that is missing fails the refresh with class configuration and keeps what it held",
        arguments: [LocalSourceFormat.calendar, .feed])
    func missingConfiguredFileIsConfiguration(_ format: LocalSourceFormat) async throws {
        try await ScratchDirectory.with { scratch in
            let file: URL
            let configured: HostSource
            if format == .calendar {
                file = scratch.path("calendars", "work.ics")
                try SourceFiles.write(SyntheticEvent.calendar([work]), to: file, modifiedAt: at("06:00"))
                configured = SourceFiles.calendarSource(file, key: "configured")
            } else {
                file = scratch.path("feeds", "news.xml")
                try SourceFiles.write(Self.feed(["Alpha"]), to: file, modifiedAt: at("06:00"))
                configured = SourceFiles.feedSource(file, key: "configured")
            }
            let testHost = testHost(scratch, sources: [configured])
            let host = try testHost.open()
            await host.runtime.runOnce()
            let events = try host.application.all(CalendarOccurrence.self).filter(\.blocksTime).count
            let items = try host.application.all(NewsItem.self).count
            #expect(events + items == 1)

            try FileManager.default.removeItem(at: file)
            await cycle(host, testHost)
            let failing = try source("configured", in: host)
            #expect(failing.isFailing)
            #expect(failing.lastFailure?.errorClass == .configuration)
            #expect(failing.lastFailure?.summary.contains(file.lastPathComponent) == true)
            #expect(try host.application.all(CalendarOccurrence.self).filter(\.blocksTime).count == events)
            #expect(try host.application.all(NewsItem.self).count == items)
            host.close()
        }
    }

    @Test("A mail directory skips an oversized message with a visible note and reads every other message once")
    func oversizedMessageIsSkippedWithNote() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("mailbox")
            let small = { (subject: String, number: Int) in
                SyntheticMail.message(
                    subject: subject, messageID: "<l07-local-\(number)@example.com>",
                    body: "A synthetic note, number \(number).\n")
            }
            try SourceFiles.write(
                small("Synthetic first", 1), named: "01-first", in: directory, receivedAt: at("06:00"))
            let large = SyntheticMail.message(
                subject: "Synthetic oversized", messageID: "<l07-local-2@example.com>",
                body: String(repeating: "A synthetic line that makes this message too large.\n", count: 100))
            try SourceFiles.write(large, named: "02-oversized", in: directory, receivedAt: at("06:01"))
            try SourceFiles.write(
                small("Synthetic third", 3), named: "03-third", in: directory, receivedAt: at("06:02"))
            let testHost = testHost(scratch, sources: [SourceFiles.mailSource(directory)])
            let host = try testHost.open()
            await host.runtime.runOnce()
            #expect(
                Set(try host.application.all(EmailMessage.self).map(\.subject)) == [
                    "Synthetic first", "Synthetic third",
                ])
            let mailbox = try source("mailbox", in: host)
            #expect(!mailbox.isFailing)
            #expect(
                mailbox.capabilityNotes.contains(
                    "02-oversized.eml is larger than \(Self.maxBytes) bytes and was skipped"))

            // Later passes read only what arrives later, never the skipped or earlier messages again.
            try SourceFiles.write(
                small("Synthetic fourth", 4), named: "04-fourth", in: directory, receivedAt: at("07:01"))
            await cycle(host, testHost)
            await cycle(host, testHost)
            let subjects = try host.application.all(EmailMessage.self).map(\.subject).sorted()
            #expect(subjects == ["Synthetic first", "Synthetic fourth", "Synthetic third"])
            host.close()
        }
    }
}
