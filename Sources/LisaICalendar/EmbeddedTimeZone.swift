// Offset rules defined by a calendar's own VTIMEZONE component (for example Outlook's Windows zone names).

import Foundation
import LisaTime

/// A VTIMEZONE definition evaluated from its STANDARD/DAYLIGHT observances.
public struct EmbeddedTimeZone: UTCOffsetRules {
    public let tzid: String
    private let transitions: [Transition]
    private let initialOffset: Int

    private struct Transition: Sendable {
        let at: Date
        let offset: Int
    }

    /// Builds the rules, or returns `nil` when the component has no usable observance.
    public init?(_ component: ICalComponent) {
        guard component.name == "VTIMEZONE", let tzid = component.property("TZID")?.value, !tzid.isEmpty else {
            return nil
        }
        var transitions: [Transition] = []
        var earliest: (Date, Int)?
        for observance in component.components where observance.name == "STANDARD" || observance.name == "DAYLIGHT" {
            guard let startLine = observance.property("DTSTART"),
                let (startLocal, _) = ICalValues.dateTime(startLine.value),
                let fromLine = observance.property("TZOFFSETFROM"), let from = ICalValues.utcOffset(fromLine.value),
                let toLine = observance.property("TZOFFSETTO"), let to = ICalValues.utcOffset(toLine.value)
            else { continue }
            var onsets = [startLocal]
            if let ruleLine = observance.property("RRULE"), let rule = RecurrenceRule.parse(ruleLine.value),
                rule.isSupported
            {
                let horizon = LocalDateTime(
                    date: LocalDate(year: 2100, month: 12, day: 31) ?? startLocal.date, time: .midnight)
                let expansion = RecurrenceExpander.expand(
                    start: startLocal, rule: rule, windowStart: startLocal, horizon: horizon,
                    isAfterUntil: { local in
                        switch rule.until {
                        case .utc(let until):
                            Date(timeIntervalSince1970: TimeInterval(local.secondsSinceEpoch - from)) > until
                        case .date(let date): local.date > date
                        case .zoned(let bound, _), .floating(let bound): local > bound
                        case nil: false
                        }
                    }, maxOccurrences: 1_000, maxIterations: 2_000)
                onsets = expansion.starts
            }
            for line in observance.properties(named: "RDATE") {
                for value in ICalValues.timeValues(line) {
                    onsets.append(value.writtenLocal)
                }
            }
            for onset in onsets {
                let instant = Date(timeIntervalSince1970: TimeInterval(onset.secondsSinceEpoch - from))
                transitions.append(Transition(at: instant, offset: to))
                if earliest == nil || instant < earliest!.0 { earliest = (instant, from) }
            }
        }
        guard let earliest else { return nil }
        self.tzid = tzid
        self.transitions = transitions.sorted { $0.at < $1.at }
        self.initialOffset = earliest.1
    }

    public func secondsFromUTC(at instant: Date) -> Int {
        var low = 0
        var high = transitions.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if transitions[middle].at <= instant {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found.map { transitions[$0].offset } ?? initialOffset
    }
}
