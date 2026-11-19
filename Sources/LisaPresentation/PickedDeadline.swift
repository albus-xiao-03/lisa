// A task's new deadline from what the owner picked: a day, or a day and a time, in the owner's zone.

import Foundation
import LisaAPIContract

/// The deadline a task edit sends, built from a date picker (UI-02: updating tasks).
///
/// A date picker holds an instant and shows it in its calendar's zone. Pass the zone the picker shows, the owner's, so
/// the deadline is the day or the time the owner saw:
/// - a day becomes a date deadline (`YYYY-MM-DD`), with no time and no zone;
/// - a day and a time becomes that moment, to the minute, with the zone's identifier.
public enum PickedDeadline {
    /// The deadline for `picked`, a date picker's value shown in `zone`: the day it shows, or with `includesTime` the
    /// moment it shows, to the minute.
    public static func deadline(_ picked: Date, includesTime: Bool, in zone: TimeZone) -> DeadlineDTO {
        guard includesTime else { return DeadlineDTO(date: LocalDay.string(for: picked, in: zone)) }
        let minute = (picked.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return DeadlineDTO(instant: Date(timeIntervalSinceReferenceDate: minute), zone: zone.identifier)
    }

    /// Where a date picker shown in `zone` starts for `deadline`: the deadline's moment, noon on its day, or `now` when
    /// there is no deadline or its date is not a `YYYY-MM-DD` calendar date.
    public static func pickerValue(for deadline: DeadlineDTO?, in zone: TimeZone, now: Date) -> Date {
        if let instant = deadline?.instant { return instant }
        guard let date = deadline?.date, let noon = noon(on: date, in: zone) else { return now }
        return noon
    }

    /// Noon on `date` (`YYYY-MM-DD`) in `zone`, or `nil` when `date` is not such a calendar date.
    private static func noon(on date: String, in zone: TimeZone) -> Date? {
        let parts = date.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
            LocalDay.string(for: noon, in: zone) == date
        else { return nil }
        return noon
    }
}
