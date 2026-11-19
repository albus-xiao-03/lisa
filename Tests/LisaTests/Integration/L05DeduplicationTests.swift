// Integration tests for L05, deduplication (MAIL-02, INGEST-01, EVENT-01, DATA-04, DATA-05; D-22, D-24, D-31, D-32,
// D-33): reimporting or refetching the same message stores it once, keeps one copy of its content (so deleting the
// message deletes it) and creates no further commitments or proposals, across sources and restarts. Mail addressing
// (addressed, copied, unknown sender, sent or forwarded by the owner) is recorded, and the owner's note is kept as the
// only text that can confirm a commitment.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaSQLite
import LisaTime
import Testing

@Suite("L05 — Deduplication", .tags(.integration))
struct L05DeduplicationTests {
    /// Monday 2026-11-16, 08:00 in New York.
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    private let colleague = "Colleague <colleague@example.com>"

    /// A direct request with a deadline, an invitation with a calendar part, and a message the owner forwarded.
    private var inbox: [(name: String, mail: SyntheticMail)] {
        let invitation = SyntheticCalendar.calendar(
            SyntheticCalendar.event(
                uid: "l05-invite@example.com", summary: "Synthetic planning session",
                "DTSTART;TZID=America/New_York:20261119T150000", "DTEND;TZID=America/New_York:20261119T160000")
        ).replacingOccurrences(of: "\r\n", with: "\n")
        return [
            (
                "m001",
                SyntheticMail.message(
                    subject: "Synthetic filing", from: colleague, to: TestHost.ownerAddress,
                    messageID: "<l05-1@example.com>",
                    body: "Task: Prepare the synthetic filing\nDue: 2026-11-20 17:00\n")
            ),
            (
                "m002",
                SyntheticMail.message(
                    subject: "Invitation: Synthetic planning session", from: colleague, to: TestHost.ownerAddress,
                    messageID: "<l05-2@example.com>", contentType: "multipart/mixed; boundary=\"l05-parts\"",
                    body: SyntheticMail.multipart(
                        boundary: "l05-parts",
                        parts: [
                            SyntheticMail.part(
                                [("Content-Type", "text/plain; charset=utf-8")], body: "Invitation attached."),
                            SyntheticMail.part(
                                [("Content-Type", "text/calendar; charset=utf-8; method=REQUEST")], body: invitation),
                        ]))
            ),
            (
                "m003",
                SyntheticMail.message(
                    subject: "Fwd: Synthetic venue", from: "Owner <\(TestHost.ownerAddress)>", to: TestHost.lisaAddress,
                    messageID: "<l05-3@example.com>",
                    body: """
                        Task: Book the synthetic venue (confirmed)

                        ---------- Forwarded message ---------
                        From: Vendor <vendor@example.com>
                        Subject: Synthetic venue

                        Task: Pay the synthetic deposit (confirmed)
                        """)
            ),
        ]
    }

    private func write(_ messages: [(name: String, mail: SyntheticMail)], to directory: URL) throws {
        for message in messages {
            try SourceFiles.write(
                message.mail, named: message.name, in: directory, receivedAt: start.addingTimeInterval(-3600))
        }
    }

    /// The number of raw content items in the host's database, read through a separate read-only connection.
    private func rawContentCount(_ testHost: TestHost) throws -> Int {
        let database = try SQLiteDatabase(
            path: testHost.dataDirectory.appendingPathComponent("lisa.sqlite").path, readOnly: true, create: false)
        return Int(
            try database.perform { try $0.query("SELECT COUNT(*) FROM raw_content") }.first?.first?.integer ?? -1)
    }

    /// Counts of what ingestion and review produced.
    private func counts(_ host: LisaHost) throws -> [Int] {
        let app = host.application
        return [
            try app.all(EmailMessage.self).count, try app.all(Evidence.self).filter { $0.kind == .email }.count,
            try app.all(LisaTask.self).count, try app.all(EventProposal.self).count,
        ]
    }

    @Test("Importing the same messages through a second source, before and after a restart, stores nothing twice")
    func reimportThroughAnotherSource() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("export")
            try write(inbox, to: directory)
            var testHost = TestHost(scratch: scratch, now: start)
            testHost.settings.model = .deterministic
            var host = try testHost.open()
            let first = try await host.importDirectory(directory, format: .mail, key: "import-a", name: "Import A")
            #expect(first.outcome.inserted == 3)
            _ = try await host.application.runCycle()
            // Three messages and their evidence; three tasks (one from the request, two from the forward); one
            // proposal from the invitation.
            let expected = [3, 3, 3, 1]
            #expect(try counts(host) == expected)
            let rawAfterFirst = try rawContentCount(testHost)
            #expect(rawAfterFirst == 3)

            let second = try await host.importDirectory(directory, format: .mail, key: "import-b", name: "Import B")
            #expect(second.outcome.inserted == 0)
            #expect(second.outcome.unchanged == 3)
            _ = try await host.application.runCycle()
            #expect(try counts(host) == expected)

            try testHost.restart(&host)
            let third = try await host.importDirectory(directory, format: .mail, key: "import-c", name: "Import C")
            #expect(third.outcome.inserted == 0)
            _ = try await host.application.runCycle()
            #expect(try counts(host) == expected)
            // A message already stored keeps one copy of its content, however often it is imported.
            let rawAfterReimports = try rawContentCount(testHost)
            #expect(rawAfterReimports == rawAfterFirst)
            // Deleting the messages deletes their content (DATA-05), so no copy of it may remain anywhere.
            for email in try host.application.all(EmailMessage.self) {
                _ = try host.application.delete(.email(email.id), by: .localOwner)
            }
            let rawAfterDeletion = try rawContentCount(testHost)
            #expect(rawAfterDeletion == 0)
            host.close()
        }
    }

    @Test("A mailbox that delivers the same messages again under new names stores and extracts them once")
    func refetchUnderNewNames() async throws {
        try await ScratchDirectory.with { scratch in
            let mailbox = scratch.path("mailbox")
            try write(inbox, to: mailbox)
            var testHost = TestHost(scratch: scratch, now: start, sources: [SourceFiles.mailSource(mailbox)])
            testHost.settings.model = .deterministic
            var host = try testHost.open()
            await host.runtime.runOnce()
            let expected = [3, 3, 3, 1]
            #expect(try counts(host) == expected)
            let tasks = try host.application.all(LisaTask.self).map(\.id).sorted()

            // The same messages arrive again, as after a mailbox resynchronization, then the host restarts.
            try write(inbox.map { (name: "z-\($0.name)", mail: $0.mail) }, to: mailbox)
            try testHost.restart(&host)
            testHost.advance(minutes: SourceFiles.syncIntervalMinutes)
            let outcome = await host.runtime.runOnce()
            #expect(outcome.synchronized.first?.outcome.inserted == 0)
            #expect(outcome.synchronized.first?.outcome.unchanged == 3)
            #expect(try counts(host) == expected)
            #expect(try host.application.all(LisaTask.self).map(\.id).sorted() == tasks)
            host.close()
        }
    }

    @Test("Addressing is recorded per message, and only the owner's own words confirm a commitment")
    func addressingAndOwnerNote() async throws {
        try await ScratchDirectory.with { scratch in
            let mailbox = scratch.path("mailbox")
            let others: [(name: String, mail: SyntheticMail)] = [
                (
                    "m004",
                    SyntheticMail.message(
                        subject: "Slides", from: colleague, to: "Other <other@example.com>",
                        cc: "Owner <\(TestHost.ownerAddress)>", messageID: "<l05-4@example.com>",
                        body: "Please send the synthetic slides by 2026-11-20.\n")
                ),
                (
                    "m005",
                    SyntheticMail.message(
                        subject: "Payment", from: "Stranger <stranger@example.invalid>",
                        to: "Someone <someone@example.invalid>", messageID: "<l05-5@example.com>",
                        body: "Task: Wire the synthetic payment (confirmed)\n")
                ),
                (
                    "m006",
                    SyntheticMail.message(
                        subject: "Agenda", from: colleague, to: TestHost.lisaAddress, messageID: "<l05-6@example.com>",
                        body: "Task: Draft the synthetic agenda (confirmed)\n")
                ),
                (
                    "m007",
                    SyntheticMail.message(
                        subject: "Note to self", from: TestHost.ownerAddress, to: TestHost.lisaAddress,
                        messageID: "<l05-7@example.com>", body: "Task: Renew the synthetic license (confirmed)\n")
                ),
            ]
            try write(inbox + others, to: mailbox)
            var testHost = TestHost(scratch: scratch, now: start, sources: [SourceFiles.mailSource(mailbox)])
            testHost.settings.model = .deterministic
            let host = try testHost.open()
            await host.runtime.runOnce()

            let emails = Dictionary(
                uniqueKeysWithValues: try host.application.all(EmailMessage.self).map {
                    ("<\($0.messageID ?? "")>", $0)
                })
            #expect(emails["<l05-1@example.com>"]?.addressing == .direct)
            #expect(emails["<l05-3@example.com>"]?.addressing == .forwardedByOwner)
            #expect(emails["<l05-4@example.com>"]?.addressing == .carbonCopy)
            #expect(emails["<l05-5@example.com>"]?.addressing == .unknownSender)
            #expect(emails["<l05-6@example.com>"]?.addressing == .direct)
            #expect(emails["<l05-7@example.com>"]?.addressing == .sentByOwner)
            // The owner's note above the forward is kept apart from the forwarded original.
            let forwarded = try #require(emails["<l05-3@example.com>"])
            #expect(forwarded.ownerNote == "Task: Book the synthetic venue (confirmed)")
            #expect(forwarded.forwardedOriginal?.from?.address == "vendor@example.com")
            #expect(forwarded.forwardedOriginal?.subject == "Synthetic venue")

            let tasks = Dictionary(
                uniqueKeysWithValues: try host.application.all(LisaTask.self).map { ($0.title, $0.confirmation) })
            #expect(
                tasks == [
                    "Prepare the synthetic filing": .possible, "Book the synthetic venue": .confirmed,
                    "Pay the synthetic deposit": .possible, "Draft the synthetic agenda": .possible,
                    "Renew the synthetic license": .confirmed,
                ])
            // A copy's request is noted for attention, not made the owner's task; an unknown sender's is neither.
            #expect(emails["<l05-4@example.com>"]?.attention?.contains { $0.contains("someone else") } == true)
            #expect(emails["<l05-5@example.com>"]?.extraction == .extracted)
            host.close()
        }
    }
}
