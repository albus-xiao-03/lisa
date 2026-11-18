// Unit tests for L22, limits (OPS-02, SEC-02, MODEL-02; D-09, D-11, D-19, D-26): oversized messages, headers, parts,
// nesting, text, HTML, calendars, lines, events and model replies are rejected or truncated visibly; recurrence
// expansion stops at its bounds; model repair and delivery backoff stay bounded; log files rotate within their size.

import Foundation
import LisaHTMLText
import LisaICalendar
import LisaInference
import LisaLogging
import LisaMIME
import LisaPolicy
import LisaTime
import Testing

@Suite("L22 — Limits", .tags(.unit))
struct L22LimitsTests {
    private func textParts(_ count: Int) -> [String] {
        (1...count).map { SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Part \($0).") }
    }

    private func parse(_ mail: SyntheticMail, limits: MIMELimits) throws -> ParsedMail {
        ParsedMail.from(try MIMEParser.parse(mail.data, limits: limits), limits: limits) { HTMLText.convert($0).text }
    }

    @Test("The documented MIME and calendar defaults are in force")
    func documentedDefaults() {
        let mime = MIMELimits()
        #expect(mime.maxMessageBytes == 25_000_000)
        #expect(mime.maxHeaderBytes == 262_144)
        #expect(mime.maxHeaderFields == 1_000)
        #expect(mime.maxDepth == 10)
        #expect(mime.maxParts == 200)
        #expect(mime.maxTextCharacters == 200_000)
        let calendar = ICalendarLimits()
        #expect(calendar.maxOccurrencesPerEvent == 1_000)
        #expect(calendar.maxTotalOccurrences == 20_000)
        #expect(calendar.maxRecurrenceIterations == 50_000)
        let model = ModelUsageLimits()
        #expect(model.maxResponseBytes == 65_536)
        #expect(model.maxItems == 25)
    }

    @Test("A message over the size limit, or with oversized headers, is rejected")
    func oversizedMessagesAreRejected() {
        let large = SyntheticMail.message(subject: "Large", body: String(repeating: "x", count: 2_048))
        #expect(throws: MIMEError.messageTooLarge) {
            try MIMEParser.parse(large.data, limits: MIMELimits(maxMessageBytes: 1_024))
        }
        let headers = SyntheticMail.message(
            subject: String(repeating: "Long subject ", count: 100), body: "Short body.")
        #expect(throws: MIMEError.headersTooLarge) {
            try MIMEParser.parse(headers.data, limits: MIMELimits(maxHeaderBytes: 512))
        }
    }

    @Test("No more header fields than the limit are read, and the truncation is visible")
    func headerFieldsAreBounded() throws {
        let extra = (1...20).map { (name: "X-Synthetic-\($0)", value: "value \($0)") }
        let mail = SyntheticMail.message(subject: "Many headers", extraHeaders: extra, body: "Body.")
        let limits = MIMELimits(maxHeaderFields: 5)
        let entity = try MIMEParser.parse(mail.data, limits: limits)
        #expect(entity.headers.fields.count <= limits.maxHeaderFields)
        #expect(!entity.warnings.isEmpty)
    }

    @Test("Parts beyond the part limit are not read, and the message says so")
    func partsAreBounded() throws {
        let mail = SyntheticMail.message(
            subject: "Many parts", contentType: "multipart/mixed; boundary=many",
            body: SyntheticMail.multipart(boundary: "many", parts: textParts(20)))
        let limits = MIMELimits(maxParts: 5)
        let entity = try MIMEParser.parse(mail.data, limits: limits)
        #expect(entity.parts.count < limits.maxParts)
        #expect(!entity.parts.isEmpty)
        let parsed = ParsedMail.from(entity, limits: limits) { HTMLText.convert($0).text }
        #expect(!parsed.text.contains("Part 20."))
        #expect(parsed.warnings.contains { $0.contains("more than 5 parts") })
    }

    @Test("Multipart nesting deeper than the limit is not read, with a warning")
    func nestingIsBounded() throws {
        var body = SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Deepest text.")
        for level in (1...6).reversed() {
            body = SyntheticMail.part(
                [("Content-Type", "multipart/mixed; boundary=level-\(level)")],
                body: SyntheticMail.multipart(boundary: "level-\(level)", parts: [body]))
        }
        let mail = SyntheticMail(
            headers: [("From", "sender@example.com"), ("Subject", "Nested"), ("MIME-Version", "1.0")]
                + [("Content-Type", "multipart/mixed; boundary=outer")],
            body: SyntheticMail.multipart(boundary: "outer", parts: [body]))
        let parsed = try parse(mail, limits: MIMELimits(maxDepth: 3))
        #expect(parsed.warnings.contains("multipart nesting deeper than 3 was not read"))
        #expect(!parsed.text.contains("Deepest text."))
    }

    @Test("Message text over the character limit is truncated with a warning")
    func textIsBounded() throws {
        let mail = SyntheticMail.message(subject: "Long", body: String(repeating: "abcdefghij", count: 100))
        let parsed = try parse(mail, limits: MIMELimits(maxTextCharacters: 100))
        #expect(parsed.text.count == 100)
        #expect(parsed.warnings.contains("the message text was truncated at 100 characters"))
    }

    @Test("HTML text and its link list are bounded")
    func htmlIsBounded() {
        let result = HTMLText.convert("<p>\(String(repeating: "word ", count: 200))</p>", maxCharacters: 50)
        #expect(result.text.count <= 51)
        #expect(result.text.hasSuffix("…"))
        let links = (1...300).map { "<a href=\"https://example.com/\($0)\">link \($0)</a>" }.joined()
        #expect(HTMLText.convert(links).links.count == 200)
    }

    @Test("Calendars over the byte, line-length, line-count or nesting limits are rejected")
    func calendarInputIsBounded() {
        let event = SyntheticCalendar.event(
            uid: "e-1", summary: String(repeating: "Long title ", count: 20), "DTSTART:20261116T150000Z")
        let text = SyntheticCalendar.calendar(event)
        #expect(throws: ICalendarError.inputTooLarge) {
            try ICalParser.parseCalendar(text, limits: ICalendarLimits(maxInputBytes: 100))
        }
        #expect(throws: ICalendarError.inputTooLarge) {
            try ICalParser.parseCalendar(Data(text.utf8), limits: ICalendarLimits(maxInputBytes: 100))
        }
        #expect(throws: ICalendarError.lineTooLong) {
            try ICalParser.parseCalendar(text, limits: ICalendarLimits(maxLineLength: 100))
        }
        let many = SyntheticCalendar.calendar(
            components: (1...20).map {
                SyntheticCalendar.event(uid: "e-\($0)", summary: "E", "DTSTART:20261116T150000Z")
            })
        #expect(throws: ICalendarError.tooManyLines) {
            try ICalParser.parseCalendar(many, limits: ICalendarLimits(maxLines: 30))
        }
        let nested = SyntheticCalendar.calendar(
            SyntheticCalendar.event(
                uid: "e-1", summary: "Alarm", "DTSTART:20261116T150000Z", "BEGIN:VALARM", "ACTION:DISPLAY",
                "END:VALARM"))
        #expect(throws: ICalendarError.nestingTooDeep) {
            try ICalParser.parseCalendar(nested, limits: ICalendarLimits(maxNestingDepth: 2))
        }
    }

    @Test("Only the configured number of events is read, with a warning and uncertainty")
    func eventCountIsBounded() throws {
        let events = (1...5).map {
            SyntheticCalendar.event(uid: "e-\($0)", summary: "Event \($0)", "DTSTART:2026111\($0)T150000Z")
        }
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(components: events),
            window: SyntheticCalendar.window("2026-11-01T00:00", "2026-12-01T00:00"),
            limits: ICalendarLimits(maxEvents: 3))
        #expect(calendar.occurrences.count == 3)
        #expect(calendar.warnings.contains { $0.message == "the calendar has 5 events; only the first 3 were read" })
        #expect(calendar.availabilityUncertain)
    }

    @Test("An endless series stops at the per-event occurrence limit, visibly")
    func endlessSeriesIsBounded() throws {
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(
                SyntheticCalendar.event(
                    uid: "forever", summary: "Forever", "DTSTART:20260101T150000Z", "DTEND:20260101T153000Z",
                    "RRULE:FREQ=DAILY")),
            window: SyntheticCalendar.window("2026-01-01T00:00", "2036-01-01T00:00"))
        #expect(calendar.occurrences.count <= ICalendarLimits().maxOccurrencesPerEvent)
        #expect(calendar.occurrences.count > 900)
        #expect(calendar.warnings.contains { $0.uid == "forever" && $0.makesAvailabilityUncertain })
        #expect(calendar.availabilityUncertain)
    }

    @Test("All series together stop at the total occurrence limit, visibly")
    func totalOccurrencesAreBounded() throws {
        let series = (1...3).map {
            SyntheticCalendar.event(
                uid: "series-\($0)", summary: "Series \($0)", "DTSTART:20261101T1\($0)0000Z",
                "RRULE:FREQ=DAILY;COUNT=30")
        }
        let limits = ICalendarLimits(maxTotalOccurrences: 50)
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(components: series),
            window: SyntheticCalendar.window("2026-11-01T00:00", "2027-01-01T00:00"), limits: limits)
        #expect(calendar.occurrences.count <= limits.maxTotalOccurrences)
        #expect(calendar.warnings.contains { $0.message.contains("more than 50 occurrences") })
        #expect(calendar.availabilityUncertain)
    }

    @Test("A rule that rarely matches stops at the iteration limit, visibly")
    func recurrenceIterationsAreBounded() throws {
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(
                SyntheticCalendar.event(
                    uid: "rare", summary: "December only", "DTSTART:20260101T150000Z", "RRULE:FREQ=DAILY;BYMONTH=12")),
            window: SyntheticCalendar.window("2026-01-01T00:00", "2027-01-01T00:00"),
            limits: ICalendarLimits(maxRecurrenceIterations: 10))
        #expect(calendar.warnings.contains { $0.uid == "rare" && $0.makesAvailabilityUncertain })
        #expect(calendar.availabilityUncertain)
    }

    @Test("Model input is truncated to its limit before anything is sent")
    func modelInputIsBounded() async throws {
        let content = UntrustedContent(String(repeating: "a", count: 20_000), minimize: false, maxCharacters: 12_000)
        #expect(content.truncated)
        #expect(content.text.count == 12_000)

        let limits = ModelUsageLimits(maxInputCharacters: 1_000, maxOutputTokens: 300)
        let provider = ScriptedModelProvider(steps: [.respond("{\"items\": []}")])
        _ = await ExtractionPipeline(provider: provider, sharing: .localOnly, limits: limits).extract(
            ExtractionRequest(
                sourceKind: "email", subject: "Subject", text: String(repeating: "b", count: 5_000),
                ownerAuthoredText: nil, addressing: .direct, referenceInstant: TestTime.utcInstant("2026-11-16T14:00"),
                zone: TestTime.newYork.timeZone, dateReading: DateReadingSettings()))
        let sent = try #require(provider.requests.first)
        #expect(sent.maxOutputTokens == 300)
        let envelope = try #require(sent.messages.last?.content)
        #expect(UntrustedContent.extract(from: envelope)?.count == 1_000)
    }

    @Test("A model that keeps answering garbage gets one repair request and no more")
    func modelRepairIsBounded() async {
        let provider = ScriptedModelProvider(steps: Array(repeating: .respond("garbage"), count: 10))
        let outcome = await ExtractionPipeline(provider: provider, sharing: .localOnly).extract(
            ExtractionRequest(
                sourceKind: "email", subject: nil, text: "Some text.", ownerAuthoredText: nil, addressing: .direct,
                referenceInstant: TestTime.utcInstant("2026-11-16T14:00"), zone: TestTime.newYork.timeZone,
                dateReading: DateReadingSettings()))
        guard case .failed = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(provider.requestCount == 2)
    }

    @Test("Retry backoff grows exponentially with jitter and never exceeds its cap")
    func backoffIsBounded() {
        for random in [0.0, 0.5, 0.999, 1.0, -3.0, 7.0] {
            var previous: TimeInterval = 0
            for attempt in 1...100 {
                let delay = DeliveryTiming.backoff(attempt: attempt, baseSeconds: 30, maxSeconds: 3_600, random: random)
                #expect(delay >= 0 && delay <= 3_600, "attempt \(attempt), random \(random)")
                #expect(delay >= previous, "attempt \(attempt), random \(random)")
                previous = delay
            }
        }
        #expect(DeliveryTiming.backoff(attempt: 1, baseSeconds: 30, maxSeconds: 3_600, random: 0) == 15)
        #expect(DeliveryTiming.backoff(attempt: 1, baseSeconds: 30, maxSeconds: 3_600, random: 1) == 30)
        #expect(DeliveryTiming.backoff(attempt: 3, baseSeconds: 30, maxSeconds: 3_600, random: 1) == 120)
        #expect(DeliveryTiming.backoff(attempt: 40, baseSeconds: 30, maxSeconds: 3_600, random: 1) == 3_600)
    }

    @Test("The log file rotates at its size limit and keeps a fixed number of old files")
    func logGrowthIsBounded() async throws {
        try await ScratchDirectory.with { scratch in
            let directory = scratch.path("logs")
            let maxBytes: UInt64 = 2_048
            do {
                let sink = try RotatingFileSink(directory: directory, maxBytes: maxBytes, keepFiles: 2)
                for index in 1...300 {
                    sink.write(
                        LogRecord(
                            timestamp: TestTime.utcInstant("2026-11-16T14:00"), level: .info, category: "tests",
                            message: "synthetic log line \(index)", metadata: ["count": .count(index)]))
                }
            }
            let names = try scratch.fileNames(in: directory)
            #expect(names == ["lisa.log", "lisa.log.1", "lisa.log.2"])
            for name in names {
                let size = try Data(contentsOf: directory.appendingPathComponent(name)).count
                #expect(UInt64(size) <= maxBytes, "\(name) is \(size) bytes")
            }
        }
    }
}
