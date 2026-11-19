// Calendar reconciliation (CAL-02): additions, material changes and cancellations from a feed or file snapshot.

import Foundation
import LisaDomain
import LisaICalendar
import LisaPorts
import LisaTime

/// Reconciles stored occurrences with a fetched calendar. Only a complete snapshot can remove occurrences, and only
/// within the expansion window; a failed or partial retrieval never deletes or cancels anything.
public struct CalendarBatchProcessor: BatchProcessor {
    public struct PreparedCalendar: Sendable {
        var occurrences: [ExpandedOccurrence]
        var warnings: [CalendarWarning]
        var window: TimeRange
        /// Read before the transaction opens: settings are never read inside one.
        var zone: TimeZone
    }

    private let settings: any SettingsSource
    private let clock: any WallClock
    private let pastDays: Int
    private let futureDays: Int
    private let limits: ICalendarLimits
    private let floatingZone: TimeZoneID?

    /// `floatingZone` is the source's configured zone for floating times and dates (CAL-01); without it, the
    /// owner's zone is used.
    public init(
        settings: any SettingsSource, clock: any WallClock, pastDays: Int = 7, futureDays: Int = 120,
        limits: ICalendarLimits = ICalendarLimits(), floatingZone: TimeZoneID? = nil
    ) {
        self.settings = settings
        self.clock = clock
        self.pastDays = pastDays
        self.futureDays = futureDays
        self.limits = limits
        self.floatingZone = floatingZone
    }

    public func prepare(_ batch: FetchBatch, source: Source) throws -> PreparedCalendar {
        let now = clock.now()
        let zone = try (floatingZone ?? settings.currentSettings().zone).timeZone
        let window = TimeRange(
            uncheckedStart: now.addingTimeInterval(-Double(pastDays) * 86_400),
            end: now.addingTimeInterval(Double(futureDays) * 86_400))
        var occurrences: [ExpandedOccurrence] = []
        var warnings: [CalendarWarning] = []
        for item in batch.items where item.kind == .calendar {
            let calendar: ICalComponent
            do {
                calendar = try ICalParser.parseCalendar(item.data, limits: limits)
            } catch {
                throw ConnectorError(.parse, "the calendar data could not be read: \(error)")
            }
            let expanded = CalendarExpander.expand(
                calendar, options: CalendarExpansionOptions(window: window, floatingZone: zone, limits: limits))
            occurrences += expanded.occurrences
            warnings += expanded.warnings
        }
        return PreparedCalendar(occurrences: occurrences, warnings: warnings, window: window, zone: zone)
    }

    public func commit(_ prepared: PreparedCalendar, batch: FetchBatch, source: Source, in tx: any RecordWriting) throws
        -> IngestionOutcome
    {
        let now = clock.now()
        let zone = prepared.zone
        var outcome = IngestionOutcome()
        let existing = try tx.find(
            CalendarOccurrence.self, RecordQuery.all.filter("source_id", equals: source.id.rawValue))
        var byKey: [String: CalendarOccurrence] = [:]
        for occurrence in existing { byKey["\(occurrence.uid)|\(occurrence.occurrenceKey)"] = occurrence }
        var seen: Set<String> = []
        for expanded in prepared.occurrences {
            let key = "\(expanded.uid)|\(expanded.occurrenceKey)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let timing = Self.timing(expanded.times)
            let status = Self.status(expanded.status)
            let availability: Availability = expanded.transparent ? .free : .busy
            if let old = byKey[key] {
                var updated = old
                updated.title = expanded.title
                updated.location = expanded.location
                updated.timing = timing
                updated.status = status
                updated.availability = availability
                updated.sequence = expanded.sequence
                updated.sourceLastModified = expanded.lastModified
                updated.warnings = expanded.warnings
                updated.lastSeenRefreshAt = now
                updated.updatedAt = now
                if updated.isMateriallyDifferent(from: old) {
                    updated.changeSequence += 1
                    outcome.updated += 1
                    outcome.changes.append(
                        status == .cancelled && old.status != .cancelled
                            ? .occurrenceCancelled(old.id)
                            : .occurrenceChanged(old.id, summary: Self.describe(old, updated)))
                } else {
                    outcome.unchanged += 1
                }
                try tx.update(updated)
            } else {
                let saved = try tx.insert(
                    CalendarOccurrence(
                        sourceID: source.id, uid: expanded.uid, occurrenceKey: expanded.occurrenceKey,
                        title: expanded.title, location: expanded.location, timing: timing, status: status,
                        availability: availability, sequence: expanded.sequence,
                        sourceLastModified: expanded.lastModified, warnings: expanded.warnings, evidenceID: nil,
                        now: now))
                outcome.inserted += 1
                outcome.changes.append(.occurrenceAdded(saved.id))
            }
        }
        if batch.isCompleteSnapshot && !batch.hasMore {
            for old in existing where !seen.contains("\(old.uid)|\(old.occurrenceKey)") && old.status != .cancelled {
                guard old.range(in: zone).overlaps(prepared.window) else { continue }
                var removed = old
                removed.status = .cancelled
                removed.warnings = Array((old.warnings + ["no longer present in the calendar source"]).suffix(5))
                removed.changeSequence += 1
                removed.updatedAt = now
                try tx.update(removed)
                outcome.updated += 1
                outcome.changes.append(.occurrenceRemoved(old.id))
            }
        } else if !existing.isEmpty, !batch.items.isEmpty {
            // An empty, non-snapshot batch means nothing changed (an HTTP "not modified" answer), not a partial read.
            outcome.warnings.append("the retrieval was not a complete snapshot, so missing events were not removed")
        }
        outcome.warnings += prepared.warnings.prefix(5).map { warning in
            (warning.makesAvailabilityUncertain ? "availability uncertain: " : "") + warning.message
        }
        return outcome
    }

    static func timing(_ times: OccurrenceTimes) -> OccurrenceTiming {
        switch times {
        case .timed(let start, let end, let tzid, let floating):
            .timed(start: start, end: end, zone: tzid.flatMap(TimeZoneID.init), floating: floating)
        case .allDay(let first, let endExclusive):
            .allDay(first: first, endExclusive: endExclusive)
        }
    }

    static func status(_ status: EventStatus) -> OccurrenceStatus {
        switch status {
        case .confirmed: .confirmed
        case .tentative: .tentative
        case .cancelled: .cancelled
        }
    }

    /// A short description of what changed, without the event's content.
    static func describe(_ old: CalendarOccurrence, _ new: CalendarOccurrence) -> String {
        var parts: [String] = []
        if old.timing != new.timing { parts.append("time changed") }
        if old.status != new.status { parts.append("status changed to \(new.status.rawValue)") }
        if old.location != new.location { parts.append("location changed") }
        if old.title != new.title { parts.append("title changed") }
        if old.availability != new.availability { parts.append("availability changed") }
        return parts.joined(separator: "; ")
    }
}
