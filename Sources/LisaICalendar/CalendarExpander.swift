// Turns VEVENTs into bounded occurrences: recurrence, EXDATE, RDATE, RECURRENCE-ID overrides, status and transparency.

import Foundation
import LisaTime

/// Expands a parsed VCALENDAR into occurrences inside a window. Unsupported constructs produce visible warnings and
/// mark availability uncertain; they never silently turn a series into a one-off event.
public enum CalendarExpander {
    public static func expand(_ calendar: ICalComponent, options: CalendarExpansionOptions) -> ExpandedCalendar {
        var context = Context(calendar: calendar, options: options)
        let events = calendar.components(named: "VEVENT")
        if events.count > options.limits.maxEvents {
            context.warn(
                nil, "the calendar has \(events.count) events; only the first \(options.limits.maxEvents) were read",
                true)
        }
        var masters: [String: ICalComponent] = [:]
        var overrides: [String: [String: ICalComponent]] = [:]
        var order: [String] = []
        for (index, event) in events.prefix(options.limits.maxEvents).enumerated() {
            var uid = event.property("UID")?.value ?? ""
            if uid.isEmpty {
                uid = "no-uid-\(index)"
                context.warn(nil, "an event has no UID; changes to it cannot be tracked reliably", false)
            }
            if let recurrence = event.property("RECURRENCE-ID") {
                if recurrence.parameter("RANGE")?.uppercased() == "THISANDFUTURE" {
                    context.warn(
                        uid, "RECURRENCE-ID;RANGE=THISANDFUTURE is not supported; later occurrences may be wrong", true)
                }
                if let value = ICalValues.timeValue(recurrence), let key = context.key(for: value) {
                    overrides[uid, default: [:]][key] = event
                }
            } else if masters[uid] == nil {
                masters[uid] = event
                order.append(uid)
            }
        }
        for uid in order {
            guard let master = masters[uid] else { continue }
            context.expandSeries(uid: uid, master: master, overrides: overrides[uid] ?? [:])
        }
        for (uid, instances) in overrides where masters[uid] == nil {
            for (key, event) in instances {
                context.addSingle(uid: uid, event: event, key: key)
            }
        }
        context.occurrences.sort { ($0.sortStart, $0.uid, $0.occurrenceKey) < ($1.sortStart, $1.uid, $1.occurrenceKey) }
        return ExpandedCalendar(
            name: calendar.property("X-WR-CALNAME").map { ICalValues.unescapeText($0.value) },
            occurrences: context.occurrences, warnings: context.warnings, eventCount: events.count)
    }

    private struct Context {
        let options: CalendarExpansionOptions
        var zones: [String: EmbeddedTimeZone] = [:]
        var occurrences: [ExpandedOccurrence] = []
        var warnings: [CalendarWarning] = []
        var warnedFloating = false

        init(calendar: ICalComponent, options: CalendarExpansionOptions) {
            self.options = options
            for component in calendar.components(named: "VTIMEZONE") {
                if let zone = EmbeddedTimeZone(component) { zones[zone.tzid] = zone }
            }
        }

        mutating func warn(_ uid: String?, _ message: String, _ uncertain: Bool) {
            warnings.append(CalendarWarning(uid: uid, message: message, makesAvailabilityUncertain: uncertain))
        }

        /// Converts a DATE-TIME value to an instant, recording how its zone was interpreted.
        mutating func instant(for value: TimeValue, uid: String) -> (Date, tzid: String?, floating: Bool)? {
            switch value {
            case .utc(let date):
                return (date, nil, false)
            case .zoned(let local, let tzid):
                if let zone = zones[tzid] { return (ZoneRules.instant(for: local, rules: zone), tzid, false) }
                if let zone = TimeZone(identifier: tzid) {
                    return (ZoneRules.instant(for: local, rules: zone), tzid, false)
                }
                warn(uid, "unknown time zone \"\(tzid)\"; interpreted in the configured floating zone", true)
                return (ZoneRules.instant(for: local, rules: options.floatingZone), nil, true)
            case .floating(let local):
                if !warnedFloating {
                    warnedFloating = true
                    warn(
                        nil, "floating times are interpreted in \(options.floatingZone.identifier) as configured", false
                    )
                }
                return (ZoneRules.instant(for: local, rules: options.floatingZone), nil, true)
            case .date:
                return nil
            }
        }

        /// The occurrence key (original start) for a DTSTART/RECURRENCE-ID/EXDATE value.
        mutating func key(for value: TimeValue) -> String? {
            switch value {
            case .date(let date):
                return date.iso.replacingOccurrences(of: "-", with: "")
            default:
                guard let (instant, _, _) = instant(for: value, uid: "") else { return nil }
                return CalendarExpander.utcKey(instant)
            }
        }

        mutating func expandSeries(uid: String, master: ICalComponent, overrides: [String: ICalComponent]) {
            guard let startLine = master.property("DTSTART"), let start = ICalValues.timeValue(startLine) else {
                warn(uid, "an event has no valid DTSTART and was skipped", true)
                return
            }
            var starts: [TimeValue] = [start]
            if let ruleLine = master.property("RRULE") {
                if let rule = RecurrenceRule.parse(ruleLine.value) {
                    if rule.isSupported {
                        starts = expandRule(
                            rule, from: start, uid: uid, durationSeconds: span(of: master, start: start))
                    } else {
                        warn(
                            uid,
                            "unsupported recurrence (\(rule.unsupported.joined(separator: ", "))); only the first occurrence is shown and availability is uncertain",
                            true)
                    }
                } else {
                    warn(
                        uid,
                        "the recurrence rule could not be read; only the first occurrence is shown and availability is uncertain",
                        true)
                }
            }
            for line in master.properties(named: "RDATE") {
                if line.parameter("VALUE")?.uppercased() == "PERIOD" {
                    warn(uid, "RDATE periods are not supported and were ignored", true)
                    continue
                }
                starts.append(contentsOf: ICalValues.timeValues(line))
            }
            var excluded = Set<String>()
            for line in master.properties(named: "EXDATE") {
                for value in ICalValues.timeValues(line) {
                    if let key = key(for: value) { excluded.insert(key) }
                }
            }
            // A one-off event keeps one stable key, so moving it is a change rather than a removal plus an addition.
            let isSeries = master.property("RRULE") != nil || !master.properties(named: "RDATE").isEmpty
            // Every instance lasts as long as the series' own DTSTART–DTEND (or DURATION), not until the master's DTEND.
            let seriesLength = span(of: master, start: start)
            var seen = Set<String>()
            var consumedOverrides = Set<String>()
            for value in starts {
                guard let key = key(for: value), !seen.contains(key) else { continue }
                seen.insert(key)
                if excluded.contains(key) { continue }
                let occurrenceKey = isSeries ? key : CalendarExpander.singleOccurrenceKey
                if let override = overrides[key] {
                    consumedOverrides.insert(key)
                    addSingle(uid: uid, event: override, key: occurrenceKey)
                } else {
                    addOccurrence(uid: uid, event: master, start: value, key: occurrenceKey, length: seriesLength)
                }
                guard occurrences.count < options.limits.maxTotalOccurrences else {
                    warn(
                        nil,
                        "the calendar produced more than \(options.limits.maxTotalOccurrences) occurrences; later ones were not read",
                        true)
                    return
                }
            }
            for (key, override) in overrides where !consumedOverrides.contains(key) {
                addSingle(uid: uid, event: override, key: key)
            }
        }

        func span(of event: ICalComponent, start: TimeValue) -> Int {
            if let duration = event.property("DURATION").flatMap({ ICalValues.duration($0.value) }) {
                return max(0, duration)
            }
            if let endLine = event.property("DTEND"), let end = ICalValues.timeValue(endLine) {
                return max(0, end.writtenLocal.secondsSinceEpoch - start.writtenLocal.secondsSinceEpoch)
            }
            return start.isDate ? 86_400 : 0
        }

        mutating func expandRule(_ rule: RecurrenceRule, from start: TimeValue, uid: String, durationSeconds: Int)
            -> [TimeValue]
        {
            let rules: any UTCOffsetRules
            switch start {
            case .utc, .date: rules = FixedOffsetRules(seconds: 0)
            case .zoned(_, let tzid):
                rules =
                    zones[tzid].map { $0 as any UTCOffsetRules } ?? TimeZone(identifier: tzid) ?? options.floatingZone
            case .floating: rules = options.floatingZone
            }
            let window = options.window
            let windowStart = ZoneRules.local(for: window.start, rules: rules).adding(
                seconds: -durationSeconds - 2 * 86_400)
            let horizon = ZoneRules.local(for: window.end, rules: rules).adding(seconds: 2 * 86_400)
            let local = start.writtenLocal
            let expansion = RecurrenceExpander.expand(
                start: local, rule: rule, windowStart: windowStart, horizon: horizon,
                isAfterUntil: { candidate in
                    switch rule.until {
                    case .utc(let until): ZoneRules.instant(for: candidate, rules: rules) > until
                    case .date(let date): candidate.date > date
                    case .zoned(let bound, _), .floating(let bound): candidate > bound
                    case nil: false
                    }
                }, maxOccurrences: options.limits.maxOccurrencesPerEvent,
                maxIterations: options.limits.maxRecurrenceIterations)
            if expansion.truncated {
                warn(uid, "recurrence expansion stopped at the configured limit; later occurrences are not shown", true)
            }
            return expansion.starts.map { candidate in
                switch start {
                case .utc: .utc(Date(timeIntervalSince1970: TimeInterval(candidate.secondsSinceEpoch)))
                case .zoned(_, let tzid): .zoned(candidate, tzid: tzid)
                case .floating: .floating(candidate)
                case .date: .date(candidate.date)
                }
            }
        }

        /// Adds one occurrence. `length` is the series' duration for recurrence instances; when it is `nil` the event's
        /// own span is used (one-off events and overrides with their own DTSTART and DTEND).
        mutating func addOccurrence(
            uid: String, event: ICalComponent, start: TimeValue, key: String, length: Int? = nil
        ) {
            let length = length ?? span(of: event, start: start)
            let times: OccurrenceTimes
            if case .date(let date) = start {
                times = .allDay(first: date, endExclusive: date.adding(days: max(1, length / 86_400)))
            } else {
                guard let (instant, tzid, floating) = instant(for: start, uid: uid) else { return }
                var end = instant.addingTimeInterval(TimeInterval(length))
                if case .zoned(let local, let zoneID) = start, length % 86_400 == 0, length > 0 {
                    // Day-based durations keep the local time across daylight-saving changes (RFC 5545 nominal days).
                    end = self.instant(for: .zoned(local.adding(seconds: length), tzid: zoneID), uid: uid)?.0 ?? end
                }
                times = .timed(start: instant, end: end, tzid: tzid, floating: floating)
            }
            let occurrence = makeOccurrence(uid: uid, event: event, times: times, key: key)
            if overlapsWindow(occurrence) { occurrences.append(occurrence) }
        }

        mutating func addSingle(uid: String, event: ICalComponent, key: String?) {
            guard let startLine = event.property("DTSTART"), let start = ICalValues.timeValue(startLine) else { return }
            let occurrenceKey = key ?? self.key(for: start) ?? "unknown"
            addOccurrence(uid: uid, event: event, start: start, key: occurrenceKey)
        }

        func makeOccurrence(uid: String, event: ICalComponent, times: OccurrenceTimes, key: String)
            -> ExpandedOccurrence
        {
            let status: EventStatus =
                switch event.property("STATUS")?.value.uppercased() {
                case "CANCELLED": .cancelled
                case "TENTATIVE": .tentative
                default: .confirmed
                }
            return ExpandedOccurrence(
                uid: uid, occurrenceKey: key,
                title: event.property("SUMMARY").map { ICalValues.unescapeText($0.value) } ?? "(untitled event)",
                location: event.property("LOCATION").map { ICalValues.unescapeText($0.value) },
                notes: event.property("DESCRIPTION").map { String(ICalValues.unescapeText($0.value).prefix(2_000)) },
                times: times, status: status,
                transparent: event.property("TRANSP")?.value.uppercased() == "TRANSPARENT",
                sequence: event.property("SEQUENCE").flatMap { Int($0.value) } ?? 0,
                lastModified: event.property("LAST-MODIFIED").flatMap { line -> Date? in
                    if case .utc(let date) = ICalValues.timeValue(line) { return date }
                    return nil
                }, warnings: [])
        }

        func overlapsWindow(_ occurrence: ExpandedOccurrence) -> Bool {
            let window = options.window
            switch occurrence.times {
            case .timed(let start, let end, _, _):
                return start < window.end && (end > window.start || (end == start && start >= window.start))
            case .allDay(let first, let endExclusive):
                let start = ZoneRules.startOfDay(first, in: options.floatingZone)
                let end = ZoneRules.startOfDay(endExclusive, in: options.floatingZone)
                return start < window.end && end > window.start
            }
        }
    }

    /// The occurrence key of an event without RRULE or RDATE. Series instances are keyed by their original start
    /// (the RECURRENCE-ID of an override), which stays the same when an instance is moved.
    public static let singleOccurrenceKey = "single"

    static func utcKey(_ instant: Date) -> String {
        let local = ZoneRules.local(for: instant, rules: FixedOffsetRules(seconds: 0))
        let date = local.date.iso.replacingOccurrences(of: "-", with: "")
        let time = String(format: "%02d%02d%02d", local.time.hour, local.time.minute, local.time.second)
        return "\(date)T\(time)Z"
    }
}

extension ExpandedOccurrence {
    var sortStart: Int64 {
        switch times {
        case .timed(let start, _, _, _): start.millisecondsSince1970
        case .allDay(let first, _): Int64(first.daysSinceEpoch) * 86_400_000
        }
    }
}
