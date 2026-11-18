// Unit tests for L04, mail parsing (MAIL-01, MAIL-02 parsing; D-12–D-14): plain text, encoded headers, transfer
// encodings, HTML-only, multipart, attachments, calendar parts, inline and attached forwards, malformed messages, and
// the owner's note and forwarded original that the parsed mail feeds into extraction.

import Foundation
import LisaHTMLText
import LisaICalendar
import LisaInference
import LisaMIME
import LisaTime
import Testing

@Suite("L04 — Mail parsing", .tags(.unit))
struct L04MailParsingTests {
    /// One inline-forward layout written by a common mail client.
    struct InlineForwardCase: Sendable, CustomTestStringConvertible {
        var client: String
        var marker: String
        var dateLine: String
        var expectedSentAt: Date?

        var testDescription: String { client }
    }

    static let inlineForwardCases = [
        InlineForwardCase(
            client: "Gmail", marker: "---------- Forwarded message ---------",
            dateLine: "Date: Mon, 16 Nov 2026 09:00:00 -0500", expectedSentAt: TestTime.utcInstant("2026-11-16T14:00")),
        InlineForwardCase(
            client: "Apple Mail", marker: "Begin forwarded message:",
            dateLine: "> Date: Mon, 16 Nov 2026 15:00:00 +0100",
            expectedSentAt: TestTime.utcInstant("2026-11-16T14:00")),
        // Zone-less dates are left unparsed rather than guessed.
        InlineForwardCase(
            client: "Outlook", marker: "-----Original Message-----",
            dateLine: "Sent: Monday, November 16, 2026 9:00 AM",
            expectedSentAt: nil),
        InlineForwardCase(
            client: "Gmail without zone", marker: "---------- Forwarded message ---------",
            dateLine: "Date: Mon, Nov 16, 2026 at 9:00 AM", expectedSentAt: nil),
    ]

    private func parse(_ mail: SyntheticMail, limits: MIMELimits = MIMELimits()) throws -> ParsedMail {
        let entity = try MIMEParser.parse(mail.data, limits: limits)
        return ParsedMail.from(entity, limits: limits) { HTMLText.convert($0).text }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("A plain-text message keeps its identity, addresses, thread references, date and text")
    func plainTextMessage() throws {
        let mail = SyntheticMail.message(
            subject: "Quarterly report", from: "\"Sender, Sam\" <Sam.Sender@Example.com>",
            to: "Lisa <lisa@example.com>, owner@example.com", cc: "Copy Person <copy@example.com>",
            extraHeaders: [
                ("In-Reply-To", "<earlier-1@example.com>"),
                ("References", "<root-1@example.com> <earlier-1@example.com>"),
            ],
            body: "Hello Lisa,\nThe report is attached.\n")
        let parsed = try parse(mail)
        #expect(parsed.messageID == "synthetic-1@example.com")
        #expect(parsed.inReplyTo == "earlier-1@example.com")
        #expect(parsed.references == ["root-1@example.com", "earlier-1@example.com"])
        #expect(parsed.from == MailAddress(displayName: "Sender, Sam", address: "sam.sender@example.com"))
        #expect(parsed.to.map(\.address) == ["lisa@example.com", "owner@example.com"])
        #expect(parsed.cc.map(\.address) == ["copy@example.com"])
        #expect(parsed.subject == "Quarterly report")
        #expect(parsed.sentAt == TestTime.utcInstant("2026-11-16T14:30"))
        #expect(trimmed(parsed.text) == "Hello Lisa,\nThe report is attached.")
        #expect(!parsed.text.unicodeScalars.contains("\r"))
        #expect(!parsed.textFromHTML)
        #expect(parsed.inlineForward == nil)
        #expect(parsed.attachedForwards.isEmpty)
        #expect(parsed.calendarParts.isEmpty)
        #expect(parsed.unsupportedAttachments.isEmpty)
        #expect(parsed.warnings.isEmpty)
    }

    @Test("Encoded headers (RFC 2047 B and Q, other charsets, adjacent words) are decoded")
    func encodedHeaders() throws {
        let base64Subject = "=?UTF-8?B?\(Data("Café meeting — notes".utf8).base64EncodedString())?="
        let mail = SyntheticMail.message(
            subject: "Re: \(base64Subject) tomorrow", from: "=?ISO-8859-1?Q?Ren=E9e_Exemple?= <renee@example.com>",
            body: "Body.")
        let parsed = try parse(mail)
        #expect(parsed.subject == "Re: Café meeting — notes tomorrow")
        #expect(parsed.from == MailAddress(displayName: "Renée Exemple", address: "renee@example.com"))
        #expect(EncodedWords.decode("=?UTF-8?Q?Caf=C3=A9?= =?UTF-8?Q?_au_lait?=") == "Café au lait")
        #expect(EncodedWords.decode("no encoded words here") == "no encoded words here")
    }

    @Test("Base64 and quoted-printable bodies decode in their declared charsets")
    func transferEncodings() throws {
        let base64 = SyntheticMail.message(
            subject: "Base64", extraHeaders: [("Content-Transfer-Encoding", "base64")],
            body: SyntheticMail.base64Lines(Data("Grüße aus Berlin — bis Freitag.".utf8)))
        #expect(trimmed(try parse(base64).text) == "Grüße aus Berlin — bis Freitag.")

        let quoted = SyntheticMail.message(
            subject: "Quoted-printable", extraHeaders: [("Content-Transfer-Encoding", "quoted-printable")],
            body: "Caf=C3=A9 au lait, =\nsoft line break and =3D sign.")
        #expect(trimmed(try parse(quoted).text) == "Café au lait, soft line break and = sign.")

        let latin1 = SyntheticMail.message(
            subject: "Latin-1", contentType: "text/plain; charset=iso-8859-1",
            extraHeaders: [("Content-Transfer-Encoding", "quoted-printable")], body: "R=E9union demain.")
        let parsed = try parse(latin1)
        #expect(trimmed(parsed.text) == "Réunion demain.")
        #expect(parsed.warnings.isEmpty)
    }

    @Test("An HTML-only message becomes sanitized text: no scripts, styles, frames, forms or remote images")
    func htmlOnlyMessage() throws {
        let html = """
            <html><head><title>Ignored title</title><style>p { color: red; }</style>\
            <script>alert('injected')</script></head>
            <body><p>Hello <b>there</b>,</p><p>The venue&nbsp;changed.</p>
            <img src="https://tracker.example.invalid/pixel.gif" alt="Company logo">
            <iframe src="https://frames.example.invalid/frame"></iframe>
            <form action="https://forms.example.invalid/submit"><input name="q" value="hidden value"></form>
            <a href="https://example.com/agenda">Agenda</a></body></html>
            """
        let parsed = try parse(
            SyntheticMail.message(subject: "Venue", contentType: "text/html; charset=utf-8", body: html))
        #expect(parsed.textFromHTML)
        #expect(parsed.text.contains("Hello there,"))
        #expect(parsed.text.contains("The venue changed."))
        #expect(parsed.text.contains("[image: Company logo]"))
        #expect(parsed.text.contains("Agenda"))
        for hidden in ["alert", "injected", "color: red", "Ignored title", "example.invalid", "hidden value", "<"] {
            #expect(!parsed.text.contains(hidden), "the text must not contain \(hidden)")
        }
        #expect(parsed.unsupportedAttachments.isEmpty)
    }

    @Test("HTML conversion lists links without fetching them and counts the removed elements")
    func htmlLinksAreListedNotFetched() {
        let result = HTMLText.convert(
            """
            <p>Read <a href="https://example.com/agenda">the agenda</a>.</p>
            <script src="https://scripts.example.invalid/x.js"></script>
            <img src="https://images.example.invalid/a.png"><object data="https://objects.example.invalid/o"></object>
            """)
        #expect(result.links == ["https://example.com/agenda"])
        #expect(result.removedElements >= 3)
        #expect(result.text == "Read the agenda.")
    }

    @Test("multipart/alternative prefers the plain part; HTML is used only when no plain part exists")
    func alternativeParts() throws {
        let plainAndHTML = SyntheticMail.multipart(
            boundary: "alt-1",
            parts: [
                SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Plain version of the note."),
                SyntheticMail.part(
                    [("Content-Type", "text/html; charset=utf-8")], body: "<p>HTML version of the note.</p>"),
            ])
        let both = try parse(
            SyntheticMail.message(
                subject: "Both", contentType: "multipart/alternative; boundary=\"alt-1\"", body: plainAndHTML))
        #expect(trimmed(both.text) == "Plain version of the note.")
        #expect(!both.textFromHTML)

        let htmlOnly = SyntheticMail.multipart(
            boundary: "alt-2",
            parts: [
                SyntheticMail.part(
                    [("Content-Type", "text/html; charset=utf-8")], body: "<p>Only <i>HTML</i> here.</p>")
            ])
        let onlyHTML = try parse(
            SyntheticMail.message(
                subject: "HTML", contentType: "multipart/alternative; boundary=alt-2", body: htmlOnly))
        #expect(trimmed(onlyHTML.text) == "Only HTML here.")
        #expect(onlyHTML.textFromHTML)
    }

    @Test("Attachments are never interpreted: each one stays visibly unsupported, and the body text excludes them")
    func attachmentsStayUnsupported() throws {
        let body = SyntheticMail.multipart(
            boundary: "mixed-1",
            parts: [
                SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "See the attached files."),
                SyntheticMail.part(
                    [
                        ("Content-Type", "application/pdf; name=\"report.pdf\""),
                        ("Content-Disposition", "attachment; filename=\"report.pdf\""),
                        ("Content-Transfer-Encoding", "base64"),
                    ], body: SyntheticMail.base64Lines(Data("%PDF-1.4 synthetic".utf8))),
                SyntheticMail.part(
                    [
                        ("Content-Type", "application/x-msdownload"),
                        ("Content-Disposition", "attachment; filename=\"setup.exe\""),
                        ("Content-Transfer-Encoding", "base64"),
                    ], body: SyntheticMail.base64Lines(Data("MZ synthetic executable".utf8))),
                SyntheticMail.part(
                    [
                        ("Content-Type", "text/plain; charset=utf-8"),
                        ("Content-Disposition", "attachment; filename=\"notes.txt\""),
                    ], body: "Attached notes that are not the message body."),
                SyntheticMail.part([("Content-Type", "image/png")], body: "not really an image"),
            ])
        let parsed = try parse(
            SyntheticMail.message(subject: "Files", contentType: "multipart/mixed; boundary=mixed-1", body: body))
        #expect(trimmed(parsed.text) == "See the attached files.")
        #expect(
            parsed.unsupportedAttachments == [
                "report.pdf (application/pdf)", "setup.exe (application/x-msdownload)", "notes.txt (text/plain)",
                "unnamed (image/png)",
            ])
        #expect(parsed.calendarParts.isEmpty)
    }

    @Test("A calendar part goes to the calendar path and reads as the same event")
    func calendarPartReachesCalendarPath() throws {
        let invitation = SyntheticCalendar.calendar(
            SyntheticCalendar.event(
                uid: "invite-1@example.com", summary: "Design review",
                "DTSTART;TZID=America/New_York:20261118T140000", "DTEND;TZID=America/New_York:20261118T150000"))
        let body = SyntheticMail.multipart(
            boundary: "inv-1",
            parts: [
                SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "You are invited."),
                SyntheticMail.part(
                    [
                        ("Content-Type", "text/calendar; charset=utf-8; method=REQUEST"),
                        ("Content-Disposition", "attachment; filename=\"invite.ics\""),
                    ], body: invitation.replacingOccurrences(of: "\r\n", with: "\n")),
            ])
        let parsed = try parse(
            SyntheticMail.message(subject: "Invitation", contentType: "multipart/mixed; boundary=inv-1", body: body))
        #expect(parsed.unsupportedAttachments.isEmpty)
        #expect(parsed.calendarParts.count == 1)
        let part = try #require(parsed.calendarParts.first)
        let calendar = CalendarExpander.expand(
            try ICalParser.parseCalendar(part),
            options: CalendarExpansionOptions(
                window: SyntheticCalendar.window("2026-11-01T00:00", "2026-12-01T00:00"),
                floatingZone: TestTime.newYork.timeZone))
        #expect(calendar.occurrences.count == 1)
        let occurrence = try #require(calendar.occurrences.first)
        #expect(occurrence.uid == "invite-1@example.com")
        #expect(occurrence.title == "Design review")
        #expect(
            occurrence.times
                == .timed(
                    start: TestTime.utcInstant("2026-11-18T19:00"), end: TestTime.utcInstant("2026-11-18T20:00"),
                    tzid: "America/New_York", floating: false))
    }

    @Test(
        "Inline forwards keep the owner's note apart from the original's sender, subject, date and body",
        arguments: L04MailParsingTests.inlineForwardCases)
    func inlineForward(_ layout: InlineForwardCase) throws {
        let body = """
            Can you take care of this by Friday?

            \(layout.marker)
            > From: Organizer <Organizer@Example.com>
            \(layout.dateLine)
            Subject: Quarterly report
            To: owner@example.com

            Please send the quarterly report by Friday.
            """
        let parsed = try parse(SyntheticMail.message(subject: "Fwd: Quarterly report", body: body))
        let forward = try #require(parsed.inlineForward)
        #expect(forward.note == "Can you take care of this by Friday?")
        #expect(forward.from?.address == "organizer@example.com")
        #expect(forward.subject == "Quarterly report")
        #expect(forward.sentAt == layout.expectedSentAt)
        #expect(forward.body == "Please send the quarterly report by Friday.")
    }

    @Test("A message forwarded as an attachment keeps the original's headers, text and calendar parts")
    func attachedForward() throws {
        let original = SyntheticMail.multipart(
            boundary: "orig-1",
            parts: [
                SyntheticMail.part(
                    [("Content-Type", "text/plain; charset=utf-8")], body: "The workshop moves to Room 4."),
                SyntheticMail.part(
                    [("Content-Type", "text/calendar; charset=utf-8")],
                    body: SyntheticCalendar.calendar(
                        SyntheticCalendar.event(
                            uid: "workshop-1@example.com", summary: "Workshop", "DTSTART:20261119T150000Z",
                            "DTEND:20261119T160000Z")
                    ).replacingOccurrences(of: "\r\n", with: "\n")),
            ])
        let embedded = SyntheticMail.part(
            [
                ("From", "Organizer <organizer@example.com>"), ("Subject", "Venue change for the workshop"),
                ("Date", "Mon, 16 Nov 2026 15:00:00 -0500"), ("MIME-Version", "1.0"),
                ("Content-Type", "multipart/mixed; boundary=orig-1"),
            ], body: original)
        let body = SyntheticMail.multipart(
            boundary: "outer-1",
            parts: [
                SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Please note the new venue."),
                SyntheticMail.part([("Content-Type", "message/rfc822")], body: embedded),
            ])
        let parsed = try parse(
            SyntheticMail.message(
                subject: "Fwd: Venue change", from: "Owner <owner@example.com>",
                contentType: "multipart/mixed; boundary=outer-1", body: body))
        #expect(trimmed(parsed.text) == "Please note the new venue.")
        #expect(parsed.inlineForward == nil)
        #expect(parsed.attachedForwards.count == 1)
        let forward = try #require(parsed.attachedForwards.first)
        #expect(forward.from?.address == "organizer@example.com")
        #expect(forward.subject == "Venue change for the workshop")
        #expect(forward.sentAt == TestTime.utcInstant("2026-11-16T20:00"))
        #expect(trimmed(forward.text) == "The workshop moves to Room 4.")
        #expect(parsed.calendarParts.count == 1)
        #expect(parsed.unsupportedAttachments.isEmpty)
    }

    @Test("Data without a header block is rejected, never read as an empty message")
    func missingHeadersAreRejected() {
        #expect(throws: MIMEError.noHeaders) { try MIMEParser.parse(Data()) }
        #expect(throws: MIMEError.noHeaders) {
            try MIMEParser.parse(Data("no header block here, only words\r\n\r\nand more words\r\n".utf8))
        }
    }

    @Test("An unclosed multipart section is read and flagged")
    func unclosedMultipartIsFlagged() throws {
        let body = SyntheticMail.multipart(
            boundary: "open-1",
            parts: [SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Text before the end.")],
            closed: false)
        let parsed = try parse(
            SyntheticMail.message(subject: "Open", contentType: "multipart/mixed; boundary=open-1", body: body))
        #expect(trimmed(parsed.text) == "Text before the end.")
        #expect(parsed.warnings.contains("a multipart section is not properly closed"))
    }

    @Test("A multipart message without a boundary is flagged and its body is still read as text")
    func multipartWithoutBoundaryIsReadAsText() throws {
        let parsed = try parse(
            SyntheticMail.message(
                subject: "No boundary", contentType: "multipart/mixed",
                body: "The body of a message without a boundary."))
        #expect(parsed.warnings.contains("a multipart part has no boundary; it was read as text"))
        #expect(parsed.text.contains("The body of a message without a boundary."))
    }

    @Test("Text in an unknown charset or with invalid bytes is flagged, never silently garbled")
    func undecodableTextIsVisible() throws {
        let invalid = SyntheticMail.message(
            subject: "Invalid bytes", extraHeaders: [("Content-Transfer-Encoding", "base64")],
            body: Data([0xFF, 0xFE, 0x41, 0xC3]).base64EncodedString())
        let invalidParsed = try parse(invalid)
        #expect(invalidParsed.text.contains("[text in unsupported or invalid charset"))
        #expect(invalidParsed.warnings.contains("a text part used an unsupported charset"))

        let unknown = SyntheticMail.message(
            subject: "Unknown charset", contentType: "text/plain; charset=x-synthetic-unknown", body: "plain words")
        let unknownParsed = try parse(unknown)
        #expect(unknownParsed.warnings.contains("a text part used an unsupported charset"))
    }

    @Test("Header lines without a colon are skipped and the remaining headers still parse")
    func malformedHeaderLinesAreSkipped() throws {
        let raw =
            "From: sender@example.com\r\nTHIS LINE HAS NO SEPARATOR\r\nSubject: Still parsed\r\n\r\nBody text.\r\n"
        let parsed = ParsedMail.from(try MIMEParser.parse(Data(raw.utf8))) { HTMLText.convert($0).text }
        #expect(parsed.from?.address == "sender@example.com")
        #expect(parsed.subject == "Still parsed")
        #expect(trimmed(parsed.text) == "Body text.")
    }

    @Test("A forwarded message feeds extraction: only the owner's note confirms; the forwarded request stays possible")
    func forwardFeedsExtraction() async throws {
        let body = """
            Task: Send the quarterly report (confirmed)

            ---------- Forwarded message ---------
            From: Organizer <organizer@example.com>
            Date: Mon, 16 Nov 2026 09:00:00 -0500
            Subject: Quarterly report

            Please send the quarterly report by Friday.
            """
        let parsed = try parse(
            SyntheticMail.message(subject: "Fwd: Quarterly report", from: "Owner <owner@example.com>", body: body))
        let forward = try #require(parsed.inlineForward)
        let outcome = await ExtractionPipeline(provider: DeterministicProvider(), sharing: .none).extract(
            ExtractionRequest(
                sourceKind: "email", subject: parsed.subject, text: parsed.text, ownerAuthoredText: forward.note,
                addressing: .forwardedByOwner, referenceInstant: try #require(parsed.sentAt),
                zone: TestTime.newYork.timeZone, dateReading: DateReadingSettings()))
        guard case .extracted(let extraction) = outcome else {
            Issue.record("expected an extraction, got \(outcome)")
            return
        }
        #expect(extraction.provider.isDeterministic)
        #expect(extraction.provider.name == "deterministic-rules")
        #expect(extraction.rejected.isEmpty)
        let commitment = try #require(extraction.items.first { $0.kind == .commitment })
        #expect(commitment.confirmation == .confirmed)
        let request = try #require(extraction.items.first { $0.kind == .request })
        #expect(request.title == "Send the quarterly report")
        #expect(request.confirmation == .possible)
        #expect(request.deadline == .date(TestTime.date("2026-11-20")))
    }

    @Test("Requests in a message the owner is only copied on are not addressed to the owner")
    func copiedMessageIsNotTheOwnersTask() async throws {
        let parsed = try parse(
            SyntheticMail.message(
                subject: "Budget", to: "colleague@example.com", cc: "owner@example.com",
                body: "Please review the budget by Friday."))
        let outcome = await ExtractionPipeline(provider: DeterministicProvider(), sharing: .none).extract(
            ExtractionRequest(
                sourceKind: "email", subject: parsed.subject, text: parsed.text, ownerAuthoredText: nil,
                addressing: .carbonCopy, referenceInstant: try #require(parsed.sentAt),
                zone: TestTime.newYork.timeZone, dateReading: DateReadingSettings()))
        guard case .extracted(let extraction) = outcome else {
            Issue.record("expected an extraction, got \(outcome)")
            return
        }
        let request = try #require(extraction.items.first)
        #expect(request.kind == .request)
        #expect(!request.addressedToOwner)
        #expect(request.confirmation != .confirmed)
    }
}
