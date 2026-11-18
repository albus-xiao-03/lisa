// Unit tests for L06, calendar semantics (CAL-01; D-03, D-11): timed and all-day events; UTC, named, embedded, floating
// and unknown zones; daily, weekly, monthly and yearly recurrence with interval, count, until and selectors; added and
// excluded dates; overridden and cancelled instances; transparency; occurrence keys; unsupported constructs; malformed
// calendars; and the .ics export (EVENT-01) reading back as the same event.

import Foundation
import LisaICalendar
import LisaTime
import Testing

@Suite("L06 — Calendar semantics", .tags(.unit))
struct L06CalendarSemanticsTests {
    /// October 2026 through February 2027 (UTC), wide enough for most series below.
    static let defaultWindow = SyntheticCalendar.window("2026-10-01T00:00", "2027-03-01T00:00")

    private func expand(
        _ components: String..., window: TimeRange = L06CalendarSemanticsTests.defaultWindow,
        floating: TimeZoneID = TestTime.newYork
    ) throws -> ExpandedCalendar {
        try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(components: components), window: window, floatingZone: floating)
    }

    private func utc(_ iso: String) -> Date {
        TestTime.utcInstant(iso)
    }

    private func starts(_ calendar: ExpandedCalendar) -> [Date] {
        calendar.occurrences.compactMap { occurrence in
            guard case .timed(let start, _, _, _) = occurrence.times else { return nil }
            return start
        }
    }

    @Test("Timed events in UTC and named zones resolve to the right instants and keep their source zone")
    func timedEvents() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "utc-1", summary: "UTC call", "DTSTART:20261116T150000Z", "DTEND:20261116T160000Z"),
            SyntheticCalendar.event(
                uid: "ny-1", summary: "New York review", "DTSTART;TZID=America/New_York:20261116T100000",
                "DTEND;TZID=America/New_York:20261116T113000"),
            SyntheticCalendar.event(
                uid: "tokyo-1", summary: "Tokyo sync", "DTSTART;TZID=Asia/Tokyo:20261117T090000", "DURATION:PT45M"))
        let byUID = Dictionary(uniqueKeysWithValues: calendar.occurrences.map { ($0.uid, $0) })
        #expect(
            byUID["utc-1"]?.times
                == .timed(start: utc("2026-11-16T15:00"), end: utc("2026-11-16T16:00"), tzid: nil, floating: false))
        #expect(
            byUID["ny-1"]?.times
                == .timed(
                    start: utc("2026-11-16T15:00"), end: utc("2026-11-16T16:30"), tzid: "America/New_York",
                    floating: false))
        #expect(
            byUID["tokyo-1"]?.times
                == .timed(
                    start: utc("2026-11-17T00:00"), end: utc("2026-11-17T00:45"), tzid: "Asia/Tokyo", floating: false))
        #expect(calendar.occurrences.allSatisfy { $0.occurrenceKey == CalendarExpander.singleOccurrenceKey })
        #expect(calendar.occurrences.allSatisfy { $0.status == .confirmed && !$0.transparent })
        #expect(calendar.warnings.isEmpty)
        #expect(!calendar.availabilityUncertain)
    }

    @Test("Floating times are read in the configured floating zone, with a visible note")
    func floatingTimes() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "float-1", summary: "Floating", "DTSTART:20261116T100000", "DTEND:20261116T110000"),
            floating: TestTime.chicago)
        let occurrence = try #require(calendar.occurrences.first)
        #expect(
            occurrence.times
                == .timed(start: utc("2026-11-16T16:00"), end: utc("2026-11-16T17:00"), tzid: nil, floating: true))
        #expect(calendar.warnings.map(\.message) == ["floating times are interpreted in America/Chicago as configured"])
        #expect(!calendar.availabilityUncertain)
    }

    @Test("A calendar's own VTIMEZONE (an Outlook-style name) is evaluated from its rules, in both seasons")
    func embeddedTimeZone() throws {
        let calendar = try expand(
            SyntheticCalendar.easternStandardTime,
            SyntheticCalendar.event(
                uid: "winter-1", summary: "Winter", "DTSTART;TZID=Eastern Standard Time:20261116T100000",
                "DTEND;TZID=Eastern Standard Time:20261116T110000"),
            SyntheticCalendar.event(
                uid: "summer-1", summary: "Summer", "DTSTART;TZID=Eastern Standard Time:20260715T100000",
                "DTEND;TZID=Eastern Standard Time:20260715T110000"),
            window: SyntheticCalendar.window("2026-01-01T00:00", "2027-01-01T00:00"))
        let byUID = Dictionary(uniqueKeysWithValues: calendar.occurrences.map { ($0.uid, $0) })
        #expect(
            byUID["winter-1"]?.times
                == .timed(
                    start: utc("2026-11-16T15:00"), end: utc("2026-11-16T16:00"), tzid: "Eastern Standard Time",
                    floating: false))
        #expect(
            byUID["summer-1"]?.times
                == .timed(
                    start: utc("2026-07-15T14:00"), end: utc("2026-07-15T15:00"), tzid: "Eastern Standard Time",
                    floating: false))
        #expect(!calendar.availabilityUncertain)
    }

    @Test("An unknown TZID is read in the floating zone with a warning, and availability becomes uncertain")
    func unknownZoneIsUncertain() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "mars-1", summary: "Elsewhere", "DTSTART;TZID=Mars/Olympus_Mons:20261116T100000",
                "DTEND;TZID=Mars/Olympus_Mons:20261116T110000"))
        let occurrence = try #require(calendar.occurrences.first)
        #expect(
            occurrence.times
                == .timed(start: utc("2026-11-16T15:00"), end: utc("2026-11-16T16:00"), tzid: nil, floating: true))
        #expect(
            calendar.warnings.contains { $0.message.contains("Mars/Olympus_Mons") && $0.makesAvailabilityUncertain })
        #expect(calendar.availabilityUncertain)
    }

    @Test("All-day events stay local dates: a date range, or one day without DTEND")
    func allDayEvents() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "conference-1", summary: "Conference", "DTSTART;VALUE=DATE:20261116", "DTEND;VALUE=DATE:20261118"),
            SyntheticCalendar.event(uid: "holiday-1", summary: "Holiday", "DTSTART;VALUE=DATE:20261126"))
        let byUID = Dictionary(uniqueKeysWithValues: calendar.occurrences.map { ($0.uid, $0) })
        #expect(
            byUID["conference-1"]?.times
                == .allDay(first: TestTime.date("2026-11-16"), endExclusive: TestTime.date("2026-11-18")))
        #expect(
            byUID["holiday-1"]?.times
                == .allDay(first: TestTime.date("2026-11-26"), endExclusive: TestTime.date("2026-11-27")))
    }

    @Test("Daily recurrence honors INTERVAL and COUNT, and every instance keeps the series' length")
    func dailyIntervalAndCount() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "daily-1", summary: "Every other day", "DTSTART;TZID=America/New_York:20261116T090000",
                "DTEND;TZID=America/New_York:20261116T093000", "RRULE:FREQ=DAILY;INTERVAL=2;COUNT=4"))
        #expect(
            starts(calendar) == [
                utc("2026-11-16T14:00"), utc("2026-11-18T14:00"), utc("2026-11-20T14:00"), utc("2026-11-22T14:00"),
            ])
        for occurrence in calendar.occurrences {
            guard case .timed(let start, let end, _, _) = occurrence.times else {
                Issue.record("expected a timed occurrence")
                continue
            }
            #expect(end.timeIntervalSince(start) == 1_800)
        }
        #expect(
            calendar.occurrences.map(\.occurrenceKey) == [
                "20261116T140000Z", "20261118T140000Z", "20261120T140000Z", "20261122T140000Z",
            ])
    }

    @Test("Weekly recurrence honors BYDAY with an inclusive UNTIL, and INTERVAL")
    func weeklyByDayUntilAndInterval() throws {
        let byDay = try expand(
            SyntheticCalendar.event(
                uid: "weekly-1", summary: "Tuesdays and Thursdays", "DTSTART;TZID=America/New_York:20261117T100000",
                "DTEND;TZID=America/New_York:20261117T110000", "RRULE:FREQ=WEEKLY;BYDAY=TU,TH;UNTIL=20261126T150000Z"))
        #expect(
            starts(byDay) == [
                utc("2026-11-17T15:00"), utc("2026-11-19T15:00"), utc("2026-11-24T15:00"), utc("2026-11-26T15:00"),
            ])

        let fortnightly = try expand(
            SyntheticCalendar.event(
                uid: "weekly-2", summary: "Fortnightly", "DTSTART;TZID=America/New_York:20261116T090000",
                "DTEND;TZID=America/New_York:20261116T100000", "RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3"))
        #expect(starts(fortnightly) == [utc("2026-11-16T14:00"), utc("2026-11-30T14:00"), utc("2026-12-14T14:00")])
    }

    @Test("Monthly recurrence: last day of the month, months without the day skipped, ordinals and BYSETPOS")
    func monthlySelectors() throws {
        let lastDay = try expand(
            SyntheticCalendar.event(
                uid: "monthly-1", summary: "Month end", "DTSTART;TZID=America/New_York:20261130T170000",
                "DTEND;TZID=America/New_York:20261130T173000", "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=4"))
        #expect(
            starts(lastDay) == [
                utc("2026-11-30T22:00"), utc("2026-12-31T22:00"), utc("2027-01-31T22:00"), utc("2027-02-28T22:00"),
            ])

        // RFC 5545: an instance on a day the month does not have is skipped, not moved.
        let thirtyFirst = try expand(
            SyntheticCalendar.event(
                uid: "monthly-2", summary: "The 31st", "DTSTART;TZID=America/New_York:20261031T120000",
                "DTEND;TZID=America/New_York:20261031T130000", "RRULE:FREQ=MONTHLY;COUNT=3"))
        #expect(starts(thirtyFirst) == [utc("2026-10-31T16:00"), utc("2026-12-31T17:00"), utc("2027-01-31T17:00")])

        let secondTuesday = try expand(
            SyntheticCalendar.event(
                uid: "monthly-3", summary: "Second Tuesday", "DTSTART;TZID=America/New_York:20261110T180000",
                "DTEND;TZID=America/New_York:20261110T190000", "RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3"))
        #expect(starts(secondTuesday) == [utc("2026-11-10T23:00"), utc("2026-12-08T23:00"), utc("2027-01-12T23:00")])

        let lastWeekday = try expand(
            SyntheticCalendar.event(
                uid: "monthly-4", summary: "Last weekday", "DTSTART;TZID=America/New_York:20261130T160000",
                "DTEND;TZID=America/New_York:20261130T170000",
                "RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3"))
        #expect(starts(lastWeekday) == [utc("2026-11-30T21:00"), utc("2026-12-31T21:00"), utc("2027-01-29T21:00")])
    }

    @Test("Yearly recurrence with BYMONTH and an ordinal BYDAY, on all-day dates")
    func yearlyOrdinal() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "yearly-1", summary: "Fourth Thursday of November", "DTSTART;VALUE=DATE:20261126",
                "RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=3"),
            window: SyntheticCalendar.window("2026-01-01T00:00", "2029-12-31T00:00"))
        #expect(
            calendar.occurrences.map(\.times) == [
                .allDay(first: TestTime.date("2026-11-26"), endExclusive: TestTime.date("2026-11-27")),
                .allDay(first: TestTime.date("2027-11-25"), endExclusive: TestTime.date("2027-11-26")),
                .allDay(first: TestTime.date("2028-11-23"), endExclusive: TestTime.date("2028-11-24")),
            ])
        #expect(calendar.occurrences.map(\.occurrenceKey) == ["20261126", "20271125", "20281123"])
    }

    @Test("EXDATE removes instances (in its zone or in UTC) and RDATE adds one with the series' length")
    func excludedAndAddedDates() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "series-x", summary: "Daily check", "DTSTART;TZID=America/New_York:20261116T100000",
                "DTEND;TZID=America/New_York:20261116T103000", "RRULE:FREQ=DAILY;COUNT=4",
                "EXDATE;TZID=America/New_York:20261117T100000", "EXDATE:20261118T150000Z",
                "RDATE;TZID=America/New_York:20261121T100000"))
        #expect(starts(calendar) == [utc("2026-11-16T15:00"), utc("2026-11-19T15:00"), utc("2026-11-21T15:00")])
        let added = try #require(calendar.occurrences.last)
        #expect(added.occurrenceKey == "20261121T150000Z")
        #expect(
            added.times
                == .timed(
                    start: utc("2026-11-21T15:00"), end: utc("2026-11-21T15:30"), tzid: "America/New_York",
                    floating: false))
    }

    @Test("An overridden instance moves but keeps its original key; a cancelled instance is marked cancelled")
    func overridesAndCancellations() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "standup-1", summary: "Standup", "DTSTART;TZID=America/New_York:20261116T100000",
                "DTEND;TZID=America/New_York:20261116T103000", "RRULE:FREQ=DAILY;COUNT=3"),
            SyntheticCalendar.event(
                uid: "standup-1", summary: "Standup (moved)", "RECURRENCE-ID;TZID=America/New_York:20261117T100000",
                "DTSTART;TZID=America/New_York:20261117T140000", "DTEND;TZID=America/New_York:20261117T143000",
                "SEQUENCE:1"),
            SyntheticCalendar.event(
                uid: "standup-1", summary: "Standup", "RECURRENCE-ID:20261118T150000Z",
                "DTSTART;TZID=America/New_York:20261118T100000", "DTEND;TZID=America/New_York:20261118T103000",
                "STATUS:CANCELLED"))
        #expect(calendar.occurrences.count == 3)
        #expect(
            calendar.occurrences.map(\.occurrenceKey) == ["20261116T150000Z", "20261117T150000Z", "20261118T150000Z"])
        let moved = calendar.occurrences[1]
        #expect(moved.title == "Standup (moved)")
        #expect(moved.sequence == 1)
        #expect(
            moved.times
                == .timed(
                    start: utc("2026-11-17T19:00"), end: utc("2026-11-17T19:30"), tzid: "America/New_York",
                    floating: false))
        #expect(calendar.occurrences.map(\.status) == [.confirmed, .confirmed, .cancelled])
    }

    @Test("Event status and transparency are kept: cancelled, tentative, confirmed; transparent is free time")
    func statusAndTransparency() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "a-cancelled", summary: "Cancelled", "DTSTART:20261116T150000Z", "DTEND:20261116T160000Z",
                "STATUS:CANCELLED"),
            SyntheticCalendar.event(
                uid: "b-tentative", summary: "Tentative", "DTSTART:20261116T170000Z", "DTEND:20261116T180000Z",
                "STATUS:TENTATIVE"),
            SyntheticCalendar.event(
                uid: "c-free", summary: "Free", "DTSTART:20261116T190000Z", "DTEND:20261116T200000Z",
                "TRANSP:TRANSPARENT"),
            SyntheticCalendar.event(
                uid: "d-busy", summary: "Busy", "DTSTART:20261116T210000Z", "DTEND:20261116T220000Z",
                "STATUS:CONFIRMED", "TRANSP:OPAQUE"))
        #expect(calendar.occurrences.map(\.uid) == ["a-cancelled", "b-tentative", "c-free", "d-busy"])
        #expect(calendar.occurrences.map(\.status) == [.cancelled, .tentative, .confirmed, .confirmed])
        #expect(calendar.occurrences.map(\.transparent) == [false, false, true, false])
    }

    @Test("A weekly series keeps its local time across the fall-back change")
    func weeklySeriesKeepsLocalTimeAcrossDaylightSaving() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "dst-1", summary: "Monday nine o'clock", "DTSTART;TZID=America/New_York:20261026T090000",
                "DTEND;TZID=America/New_York:20261026T100000", "RRULE:FREQ=WEEKLY;COUNT=3"))
        #expect(starts(calendar) == [utc("2026-10-26T13:00"), utc("2026-11-02T14:00"), utc("2026-11-09T14:00")])
        #expect(
            starts(calendar).map { TestTime.localTime(of: $0, in: TestTime.newYork) } == ["09:00", "09:00", "09:00"])
    }

    @Test("Only occurrences overlapping the window are returned")
    func windowBoundsOccurrences() throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "a-overlaps-start", summary: "Late", "DTSTART:20261115T233000Z", "DTEND:20261116T003000Z"),
            SyntheticCalendar.event(
                uid: "b-inside", summary: "Inside", "DTSTART:20261116T120000Z", "DTEND:20261116T130000Z"),
            SyntheticCalendar.event(
                uid: "c-touches-end", summary: "Next day", "DTSTART:20261117T000000Z", "DTEND:20261117T010000Z"),
            SyntheticCalendar.event(
                uid: "d-before", summary: "Before", "DTSTART:20261115T100000Z", "DTEND:20261115T110000Z"),
            window: SyntheticCalendar.window("2026-11-16T00:00", "2026-11-17T00:00"))
        #expect(calendar.occurrences.map(\.uid) == ["a-overlaps-start", "b-inside"])
        #expect(calendar.eventCount == 4)
    }

    @Test(
        "An unsupported recurrence keeps the first occurrence, warns visibly and makes availability uncertain",
        arguments: [
            "FREQ=HOURLY;COUNT=5", "FREQ=DAILY;BYHOUR=9,17;COUNT=4", "FREQ=YEARLY;BYWEEKNO=20",
            "FREQ=WEEKLY;BYDAY=1MO;COUNT=3", "FREQ=WEEKLY;BYMONTHDAY=15;COUNT=3", "FREQ=SOMETIMES",
        ])
    func unsupportedRecurrenceIsConservative(rule: String) throws {
        let calendar = try expand(
            SyntheticCalendar.event(
                uid: "unsupported-1", summary: "Odd series", "DTSTART;TZID=America/New_York:20261116T090000",
                "DTEND;TZID=America/New_York:20261116T100000", "RRULE:\(rule)"))
        #expect(starts(calendar) == [utc("2026-11-16T14:00")])
        let warning = try #require(calendar.warnings.first { $0.uid == "unsupported-1" })
        #expect(warning.makesAvailabilityUncertain)
        #expect(warning.message.contains("only the first occurrence is shown"))
        #expect(calendar.availabilityUncertain)
    }

    @Test("RDATE periods and RANGE=THISANDFUTURE overrides are flagged and make availability uncertain")
    func otherUnsupportedConstructs() throws {
        let periods = try expand(
            SyntheticCalendar.event(
                uid: "period-1", summary: "Periods", "DTSTART:20261116T150000Z", "DTEND:20261116T160000Z",
                "RDATE;VALUE=PERIOD:20261118T150000Z/20261118T160000Z"))
        #expect(periods.availabilityUncertain)
        #expect(periods.warnings.contains { $0.message.contains("RDATE periods") })

        let future = try expand(
            SyntheticCalendar.event(
                uid: "range-1", summary: "Series", "DTSTART:20261116T150000Z", "DTEND:20261116T160000Z",
                "RRULE:FREQ=DAILY;COUNT=3"),
            SyntheticCalendar.event(
                uid: "range-1", summary: "Series (changed)", "RECURRENCE-ID;RANGE=THISANDFUTURE:20261117T150000Z",
                "DTSTART:20261117T170000Z", "DTEND:20261117T180000Z"))
        #expect(future.availabilityUncertain)
        #expect(future.warnings.contains { $0.message.contains("THISANDFUTURE") })
    }

    @Test("Malformed calendars fail as a whole instead of reading as empty")
    func malformedCalendarsFail() {
        #expect(throws: ICalendarError.unbalancedComponents("VEVENT")) {
            try ICalParser.parseCalendar("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nEND:VCALENDAR\r\n")
        }
        #expect(throws: ICalendarError.notACalendar) {
            try ICalParser.parseCalendar("BEGIN:VCARD\r\nFN:Synthetic Person\r\nEND:VCARD\r\n")
        }
        #expect(throws: ICalendarError.notUTF8) {
            try ICalParser.parseCalendar(Data([0x42, 0x45, 0xFF, 0xFE, 0x0D, 0x0A]))
        }
    }

    @Test("Events without DTSTART or UID are reported; a missing start makes availability uncertain")
    func incompleteEventsAreReported() throws {
        let noStart = try expand(SyntheticCalendar.event(uid: "nostart-1", summary: "No start", "DURATION:PT1H"))
        #expect(noStart.occurrences.isEmpty)
        #expect(noStart.warnings.contains { $0.uid == "nostart-1" && $0.makesAvailabilityUncertain })
        #expect(noStart.availabilityUncertain)

        let noUID = try expand(
            ["BEGIN:VEVENT", "SUMMARY:No UID", "DTSTART:20261116T150000Z", "DTEND:20261116T160000Z", "END:VEVENT"]
                .joined(separator: "\n"))
        #expect(noUID.occurrences.count == 1)
        #expect(noUID.warnings.contains { $0.message.contains("no UID") && !$0.makesAvailabilityUncertain })
    }

    @Test("An .ics export reads back as the same event, with escaped text and lines folded at 75 octets")
    func exportReadsBack() throws {
        let title = "Dinner; with \"friends\", maybe\\ later — a long title that needs folding across lines"
        let notes = String(repeating: "Notes, with commas; and semicolons. ", count: 6)
        let text = ICalendarWriter.write(
            [
                ExportEvent(
                    uid: "proposal-1@lisa.example", title: title,
                    start: .instant(utc("2026-11-20T23:00"), end: utc("2026-11-21T01:00")), location: "Café, Main St",
                    notes: notes),
                ExportEvent(
                    uid: "proposal-2@lisa.example", title: "Day off",
                    start: .date(TestTime.date("2026-11-27"), endExclusive: nil)),
            ], stamp: utc("2026-11-16T12:00"))
        for line in text.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75, "line too long: \(line)")
        }
        let calendar = try SyntheticCalendar.expand(text, window: L06CalendarSemanticsTests.defaultWindow)
        #expect(calendar.occurrences.count == 2)
        let dinner = try #require(calendar.occurrences.first { $0.uid == "proposal-1@lisa.example" })
        #expect(dinner.title == title)
        #expect(dinner.location == "Café, Main St")
        #expect(dinner.notes == notes)
        #expect(
            dinner.times
                == .timed(start: utc("2026-11-20T23:00"), end: utc("2026-11-21T01:00"), tzid: nil, floating: false))
        let dayOff = try #require(calendar.occurrences.first { $0.uid == "proposal-2@lisa.example" })
        #expect(dayOff.times == .allDay(first: TestTime.date("2026-11-27"), endExclusive: TestTime.date("2026-11-28")))
    }
}
