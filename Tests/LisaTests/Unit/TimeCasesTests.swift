// Unit tests for the R1 §16.3 time cases that the engines decide (DATA-03, CAL-01, PLAN-02, REM-02; D-03, D-04,
// D-05, D-11, D-15, D-16): spring-forward and fall-back transitions, a date-only deadline, an ambiguous relative date,
// and a time-zone change after a plan exists.

import Foundation
import LisaDomain
import LisaICalendar
import LisaInference
import LisaPlanning
import LisaPolicy
import LisaTime
import Testing

@Suite("§16.3 — Time cases", .tags(.unit))
struct TimeCasesTests {
    private let newYork = TestTime.newYork

    private func utc(_ iso: String) -> Date {
        TestTime.utcInstant(iso)
    }

    private func planner(
        window: (String, String), items: [PlanningItem], calendar: [CalendarBlock] = [], date: String,
        zone: TimeZoneID = TestTime.newYork, now: Date, previous: [PlanBlock] = []
    ) -> (input: PlanningInput, output: PlanningOutput) {
        let settings = PlanningSettings(
            windows: [LocalWindow(start: TestTime.time(window.0), end: TestTime.time(window.1))], maximumAllocation: 1)
        let input = PlanningFixture.input(
            calendar: calendar, tasks: items.filter { $0.kind == .task }, ideas: items.filter { $0.kind == .idea },
            settings: settings, previousBlocks: previous, date: TestTime.date(date), zone: zone, now: now)
        return (input, DeterministicPlanner.plan(input))
    }

    private func starts(_ calendar: ExpandedCalendar) -> [Date] {
        calendar.occurrences.compactMap { occurrence in
            guard case .timed(let start, _, _, _) = occurrence.times else { return nil }
            return start
        }
    }

    // MARK: Spring forward (America/New_York, 2026-03-08 02:00 EST → 03:00 EDT)

    @Test("Spring forward: a time in the gap moves later by the gap, and the day is 23 hours long")
    func springForwardGap() {
        let zone = newYork.timeZone
        #expect(
            ZoneRules.resolve(TestTime.local("2026-03-08T02:30"), in: zone)
                == .gap(shifted: utc("2026-03-08T07:30"), gapSeconds: 3_600))
        #expect(TestTime.instant("2026-03-08T02:30", in: newYork) == utc("2026-03-08T07:30"))
        #expect(TestTime.localTime(of: utc("2026-03-08T07:30"), in: newYork) == "03:30")
        #expect(ZoneRules.resolve(TestTime.local("2026-03-08T01:59"), in: zone) == .exact(utc("2026-03-08T06:59")))
        #expect(ZoneRules.resolve(TestTime.local("2026-03-08T03:00"), in: zone) == .exact(utc("2026-03-08T07:00")))
        #expect(ZoneRules.dayRange(TestTime.date("2026-03-08"), in: zone).duration == 23 * 3_600)
    }

    @Test("Spring forward: a planning window across the gap holds only its real two hours")
    func springForwardPlanning() {
        let now = TestTime.instant("2026-03-07T12:00", in: TestTime.newYork)
        let long = PlanningFixture.item(.task, id: "long", minutes: 150)
        let fits = PlanningFixture.item(.task, id: "fits", minutes: 120)
        let tooLong = planner(window: ("01:00", "04:00"), items: [long], date: "2026-03-08", now: now).output
        #expect(tooLong.blocks.isEmpty)
        #expect(tooLong.unscheduled.map(\.subject) == [long.subject])
        let (input, output) = planner(window: ("01:00", "04:00"), items: [fits], date: "2026-03-08", now: now)
        #expect(
            output.blocks.map(\.range) == [
                TimeRange(uncheckedStart: utc("2026-03-08T06:00"), end: utc("2026-03-08T08:00"))
            ])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("Spring forward: a daily event at 02:30 shifts to 03:30 on the transition day only")
    func springForwardRecurrence() throws {
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(
                SyntheticCalendar.event(
                    uid: "early-1", summary: "Early job", "DTSTART;TZID=America/New_York:20260307T023000",
                    "DTEND;TZID=America/New_York:20260307T030000", "RRULE:FREQ=DAILY;COUNT=3")),
            window: SyntheticCalendar.window("2026-03-01T00:00", "2026-03-15T00:00"))
        #expect(starts(calendar) == [utc("2026-03-07T07:30"), utc("2026-03-08T07:30"), utc("2026-03-09T06:30")])
    }

    @Test("Spring forward: quiet hours that night end at 07:00 EDT, eight real hours after they begin")
    func springForwardQuietHours() {
        let quiet = QuietHours.defaultValue
        let zone = newYork.timeZone
        #expect(quiet.nextAllowedInstant(after: utc("2026-03-08T06:00"), in: zone) == utc("2026-03-08T11:00"))
        #expect(quiet.contains(utc("2026-03-08T03:00"), in: zone))
        #expect(!quiet.contains(utc("2026-03-08T11:00"), in: zone))
    }

    // MARK: Fall back (America/New_York, 2026-11-01 02:00 EDT → 01:00 EST)

    @Test("Fall back: a repeated time resolves to the earlier instant unless the later one is asked for")
    func fallBackOverlap() {
        let zone = newYork.timeZone
        #expect(
            ZoneRules.resolve(TestTime.local("2026-11-01T01:30"), in: zone)
                == .overlap(earlier: utc("2026-11-01T05:30"), later: utc("2026-11-01T06:30")))
        #expect(TestTime.instant("2026-11-01T01:30", in: newYork) == utc("2026-11-01T05:30"))
        #expect(TestTime.instant("2026-11-01T01:30", in: newYork, preferLater: true) == utc("2026-11-01T06:30"))
        #expect(ZoneRules.dayRange(TestTime.date("2026-11-01"), in: zone).duration == 25 * 3_600)
    }

    @Test("Fall back: a planning window across the repeated hour holds its real four hours")
    func fallBackPlanning() {
        let now = TestTime.instant("2026-10-31T12:00", in: TestTime.newYork)
        let fits = PlanningFixture.item(.task, id: "fits", minutes: 210)
        let (input, output) = planner(window: ("00:00", "03:00"), items: [fits], date: "2026-11-01", now: now)
        #expect(
            output.blocks.map(\.range) == [
                TimeRange(uncheckedStart: utc("2026-11-01T04:00"), end: utc("2026-11-01T07:30"))
            ])
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
        let tooLong = PlanningFixture.item(.task, id: "too-long", minutes: 250)
        #expect(
            planner(window: ("00:00", "03:00"), items: [tooLong], date: "2026-11-01", now: now).output.blocks.isEmpty)
    }

    @Test("Fall back: a daily 01:30 event uses the first 01:30, and a one-day event lasts 25 real hours")
    func fallBackRecurrence() throws {
        let calendar = try SyntheticCalendar.expand(
            SyntheticCalendar.calendar(
                SyntheticCalendar.event(
                    uid: "night-1", summary: "Night job", "DTSTART;TZID=America/New_York:20261031T013000",
                    "DTEND;TZID=America/New_York:20261031T020000", "RRULE:FREQ=DAILY;COUNT=3"),
                SyntheticCalendar.event(
                    uid: "day-1", summary: "Whole day", "DTSTART;TZID=America/New_York:20261031T120000",
                    "DURATION:P1D")),
            window: SyntheticCalendar.window("2026-10-25T00:00", "2026-11-08T00:00"))
        let night = calendar.occurrences.filter { $0.uid == "night-1" }
        #expect(
            night.map(\.times).compactMap { times -> Date? in
                guard case .timed(let start, _, _, _) = times else { return nil }
                return start
            } == [utc("2026-10-31T05:30"), utc("2026-11-01T05:30"), utc("2026-11-02T06:30")])
        let day = try #require(calendar.occurrences.first { $0.uid == "day-1" })
        #expect(
            day.times
                == .timed(
                    start: utc("2026-10-31T16:00"), end: utc("2026-11-01T17:00"), tzid: "America/New_York",
                    floating: false))
    }

    @Test("Fall back: quiet hours that night end at 07:00 EST, ten real hours after they begin")
    func fallBackQuietHours() {
        let quiet = QuietHours.defaultValue
        let zone = newYork.timeZone
        #expect(quiet.nextAllowedInstant(after: utc("2026-11-01T05:30"), in: zone) == utc("2026-11-01T12:00"))
        #expect(quiet.nextAllowedInstant(after: utc("2026-11-01T06:30"), in: zone) == utc("2026-11-01T12:00"))
        #expect(quiet.contains(utc("2026-11-01T02:00"), in: zone))
    }

    // MARK: A date-only deadline

    @Test("A date-only deadline stays a local date in every zone; its planning boundary is the end of that day")
    func dateOnlyDeadlineKeepsItsMeaning() throws {
        let deadline = Deadline.onDate(TestTime.date("2026-11-20"))
        #expect(!deadline.isTimed)
        #expect(deadline.localDate(in: newYork.timeZone) == TestTime.date("2026-11-20"))
        #expect(deadline.localDate(in: TestTime.tokyo.timeZone) == TestTime.date("2026-11-20"))
        #expect(deadline.latestInstant(in: newYork.timeZone) == utc("2026-11-21T05:00"))
        #expect(deadline.latestInstant(in: TestTime.tokyo.timeZone) == utc("2026-11-20T15:00"))
        let encoded = String(decoding: try JSONEncoder().encode(deadline), as: UTF8.self)
        #expect(encoded.contains("2026-11-20"))
        #expect(!encoded.contains("T00") && !encoded.contains("00:00"))
        #expect(try JSONDecoder().decode(Deadline.self, from: Data(encoded.utf8)) == deadline)
        let timed = Deadline.at(instant: utc("2026-11-20T03:00"), zone: newYork)
        #expect(timed.localDate(in: newYork.timeZone) == TestTime.date("2026-11-19"))
        #expect(timed.localDate(in: TestTime.tokyo.timeZone) == TestTime.date("2026-11-20"))
    }

    @Test("A date-only deadline lets work run to the end of its day, and passes once the day is over")
    func dateOnlyDeadlinePlanning() {
        let now = TestTime.instant("2026-11-16T07:00", in: TestTime.newYork)
        let today = PlanningFixture.item(
            .task, id: "today", minutes: 30, deadline: .onDate(TestTime.date("2026-11-16")))
        let yesterday = PlanningFixture.item(
            .task, id: "yesterday", minutes: 30, deadline: .onDate(TestTime.date("2026-11-15")))
        let (input, output) = planner(
            window: ("09:00", "17:00"), items: [today, yesterday],
            calendar: [PlanningFixture.busy("busy-1", "09:00", "16:30")], date: "2026-11-16", now: now)
        #expect(
            output.blocks.filter { $0.subject == today.subject }.map(\.range) == [
                TestTime.range("16:30", "17:00", on: "2026-11-16", in: TestTime.newYork)
            ])
        #expect(output.unscheduled.first { $0.subject == yesterday.subject }?.reason == "The deadline has passed")
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }

    @Test("A date-only deadline is reminded only at a configured time, and is overdue only after its day")
    func dateOnlyDeadlineReminders() throws {
        let created = TestTime.instant("2026-11-16T09:00", in: TestTime.newYork)
        let task = SyntheticTask.confirmed(deadline: .onDate(TestTime.date("2026-11-20")), createdAt: created)
        let zone = newYork.timeZone
        #expect(
            ReminderPlanner.deadlineReminders(for: task, settings: ReminderSettings(), zone: zone, now: created) == [])
        let configured = ReminderSettings(dateOnlyReminderTime: TestTime.time("08:00"))
        let reminders = ReminderPlanner.deadlineReminders(for: task, settings: configured, zone: zone, now: created)
        #expect(reminders.map(\.dueAt) == [TestTime.instant("2026-11-20T08:00", in: TestTime.newYork)])
        #expect(reminders.map(\.rule) == [.dateOnlyDeadline])
        let lateThatDay = TestTime.instant("2026-11-20T23:00", in: TestTime.newYork)
        #expect(ReminderPlanner.overdueReminder(for: task, settings: configured, zone: zone, now: lateThatDay) == nil)
        let nextDay = TestTime.instant("2026-11-21T00:30", in: TestTime.newYork)
        let overdue = try #require(
            ReminderPlanner.overdueReminder(for: task, settings: configured, zone: zone, now: nextDay))
        #expect(overdue.dueAt == TestTime.instant("2026-11-21T09:00", in: TestTime.newYork))
    }

    @Test("A weekday in text resolves to a date with no invented time of day")
    func dateOnlyFromText() {
        let resolver = RelativeDateResolver(referenceDate: TestTime.date("2026-11-16"))
        #expect(resolver.resolve("Friday") == .resolved(TestTime.date("2026-11-20")))
        #expect(resolver.resolve("by Friday.") == .resolved(TestTime.date("2026-11-20")))
    }

    // MARK: An ambiguous relative date

    @Test("Ambiguous dates stay unresolved with every candidate")
    func ambiguousDatesStayUnresolved() {
        let resolver = RelativeDateResolver(referenceDate: TestTime.date("2026-11-16"))
        guard case .ambiguous(let fridays, _) = resolver.resolve("next Friday"),
            case .ambiguous(let mondays, _) = resolver.resolve("Monday"),
            case .ambiguous(let numeric, _) = resolver.resolve("03/04/2027"),
            case .ambiguous(let past, _) = resolver.resolve("March 3")
        else {
            Issue.record("each phrase must stay ambiguous")
            return
        }
        #expect(fridays == [TestTime.date("2026-11-20"), TestTime.date("2026-11-27")])
        #expect(mondays == [TestTime.date("2026-11-16"), TestTime.date("2026-11-23")])
        #expect(numeric == [TestTime.date("2027-03-04"), TestTime.date("2027-04-03")])
        #expect(past == [TestTime.date("2026-03-03"), TestTime.date("2027-03-03")])
    }

    @Test("Only an explicit owner setting settles an ambiguous date")
    func settingsSettleAmbiguity() {
        let reference = TestTime.date("2026-11-16")
        func resolve(_ phrase: String, _ settings: DateReadingSettings) -> DateResolution {
            RelativeDateResolver(referenceDate: reference, settings: settings).resolve(phrase)
        }
        #expect(
            resolve("03/04/2027", DateReadingSettings(numericDateOrder: .dayFirst))
                == .resolved(TestTime.date("2027-04-03")))
        #expect(
            resolve("03/04/2027", DateReadingSettings(numericDateOrder: .monthFirst))
                == .resolved(TestTime.date("2027-03-04")))
        #expect(
            resolve("next Friday", DateReadingSettings(nextWeekday: .nearestUpcoming))
                == .resolved(TestTime.date("2026-11-20")))
        #expect(
            resolve("next Friday", DateReadingSettings(nextWeekday: .followingWeek))
                == .resolved(TestTime.date("2026-11-27")))
    }

    @Test("Unambiguous phrases resolve against the reference date")
    func unambiguousPhrasesResolve() {
        let resolver = RelativeDateResolver(referenceDate: TestTime.date("2026-11-16"))
        let expected: [(String, String)] = [
            ("today", "2026-11-16"), ("tomorrow", "2026-11-17"), ("in 3 days", "2026-11-19"),
            ("in two weeks", "2026-11-30"),
            ("this Friday", "2026-11-20"), ("2026-11-30", "2026-11-30"), ("Dec 1", "2026-12-01"),
            ("13/04/2027", "2027-04-13"),
        ]
        for (phrase, date) in expected {
            #expect(resolver.resolve(phrase) == .resolved(TestTime.date(date)), "\(phrase)")
        }
        #expect(resolver.resolve("sometime soon") == .unrecognized)
    }

    @Test("Relative dates resolve against the source timestamp in the source's zone")
    func relativeDatesUseTheSourceZone() {
        let sentAt = utc("2026-11-17T03:30")
        #expect(
            RelativeDateResolver(reference: sentAt, zone: newYork.timeZone).resolve("tomorrow")
                == .resolved(TestTime.date("2026-11-17")))
        #expect(
            RelativeDateResolver(reference: sentAt, zone: TimeZoneID.utc.timeZone).resolve("tomorrow")
                == .resolved(TestTime.date("2026-11-18")))
        #expect(
            RelativeDateResolver(reference: sentAt, zone: TestTime.tokyo.timeZone).resolve("tomorrow")
                == .resolved(TestTime.date("2026-11-18")))
    }

    @Test("An unresolved deadline is no constraint: the task gets no deadline reminders and is not urgent")
    func unresolvedDeadlineIsNoConstraint() {
        let created = TestTime.instant("2026-11-16T09:00", in: TestTime.newYork)
        var task = SyntheticTask.confirmed(deadline: nil, createdAt: created)
        task.unresolvedDeadlineText = "next Friday"
        #expect(
            ReminderPlanner.deadlineReminders(
                for: task, settings: ReminderSettings(), zone: newYork.timeZone, now: created) == [])
        #expect(!UrgencyRule.isUrgentDeadline(task, now: created, windowMinutes: 15))
    }

    // MARK: A time-zone change after a plan exists

    @Test("After a zone change the day is planned in the new zone's windows; fixed instants stay where they are")
    func zoneChangeReplansInTheNewZone() {
        let newYorkPlan = DeterministicPlanner.plan(PlanningFixture.input(calendar: [PlanningFixture.busyEvent]))
        let input = PlanningFixture.input(calendar: [PlanningFixture.busyEvent], zone: TestTime.losAngeles)
        let losAngelesPlan = DeterministicPlanner.plan(input)
        let zone = TestTime.losAngeles.timeZone
        let event = losAngelesPlan.blocks.first { $0.kind == .fixedEvent }
        #expect(event?.range == PlanningFixture.busyEvent.range)
        #expect(event.map { PlanConstraintCheck.describe($0.range, in: zone) } == "07:00–08:00")
        let idea = losAngelesPlan.blocks.first { $0.subject == PlanningFixture.idea.subject }
        #expect(idea.map { PlanConstraintCheck.describe($0.range, in: zone) } == "09:00–09:30")
        // The task's deadline is an instant, 10:00 in New York, which is before the Los Angeles window opens.
        #expect(
            losAngelesPlan.unscheduled.first { $0.subject == PlanningFixture.task.subject }?.reason
                == "No free interval of 30 minutes is left before the deadline")
        #expect(PlanConstraintCheck.violations(of: losAngelesPlan, for: input) == [])
        #expect(
            Plan.key(date: PlanningFixture.date, zone: PlanningFixture.zone)
                != Plan.key(date: PlanningFixture.date, zone: TestTime.losAngeles))

        let changes = PlanDiff.explain(previous: newYorkPlan.blocks, current: losAngelesPlan.blocks, zone: zone)
        #expect(changes.contains("Moved \"Fixture idea\" from 06:30–07:00 to 09:00–09:30"))
        #expect(changes.contains("\"Fixture task\" no longer fits and is listed as unscheduled"))
    }

    @Test("After a zone change a date-only deadline keeps its date and ends with the new zone's day")
    func zoneChangeKeepsDateOnlyMeaning() {
        let item = PlanningFixture.item(
            .task, id: "date-only", minutes: 30, deadline: .onDate(TestTime.date("2026-11-16")))
        for zone in [TestTime.newYork, TestTime.losAngeles] {
            let (input, output) = planner(
                window: ("09:00", "12:00"), items: [item], date: "2026-11-16", zone: zone, now: PlanningFixture.now)
            let block = output.blocks.first { $0.subject == item.subject }
            #expect(block.map { PlanConstraintCheck.describe($0.range, in: zone.timeZone) } == "09:00–09:30", "\(zone)")
            #expect(PlanConstraintCheck.violations(of: output, for: input) == [], "\(zone)")
        }
        let deadline = Deadline.onDate(TestTime.date("2026-11-16"))
        #expect(deadline.latestInstant(in: TestTime.losAngeles.timeZone) == utc("2026-11-17T08:00"))
    }

    @Test("After a zone change, blocks the owner held keep their instants and new proposals go around them")
    func zoneChangeKeepsHeldBlocks() {
        let idea = PlanningFixture.idea
        let locked = PlanningFixture.block("idea:fixture-idea#0", for: idea, "09:30", "10:00", state: .locked)
        let other = PlanningFixture.item(.task, id: "other", minutes: 30)
        let input = PlanningFixture.input(
            calendar: [], tasks: [other], ideas: [idea], previousBlocks: [locked], zone: TestTime.losAngeles)
        let output = DeterministicPlanner.plan(input)
        #expect(output.blocks.contains(locked))
        #expect(PlanConstraintCheck.describe(locked.range, in: TestTime.losAngeles.timeZone) == "06:30–07:00")
        #expect(
            output.blocks.first { $0.subject == other.subject }.map {
                PlanConstraintCheck.describe($0.range, in: TestTime.losAngeles.timeZone)
            } == "09:00–09:30")
        #expect(PlanConstraintCheck.violations(of: output, for: input) == [])
    }
}
