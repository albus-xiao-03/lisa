// Calendar occurrences are partitioned by UTC day (plan §8.4.2): bucket n covers [n × 86,400,000, (n + 1) × 86,400,000)
// milliseconds since the epoch. An occurrence belongs to every bucket its interval overlaps, by R1's overlap rule: a
// timed event's [start, end), a zero-length event's start, and an all-day event's dates widened by one day on each
// side, buckets day(first) − 1 through day(endExclusive), so its membership never depends on the planning zone
// (every zone from UTC−12 to UTC+14 keeps it inside). A membership is therefore a contiguous range of buckets.

/// UTC-day buckets and their partitions.
public enum CalendarBuckets {
    public static let bucketMilliseconds: Int64 = 86_400_000
    /// The partition name prefix of calendar buckets.
    public static let partitionPrefix = "occurrences/"

    /// The bucket holding `milliseconds` since the epoch (floor division, so instants before 1970 work too).
    public static func bucket(ofInstant milliseconds: Int64) -> Int64 {
        let quotient = milliseconds / bucketMilliseconds
        return milliseconds % bucketMilliseconds < 0 ? quotient - 1 : quotient
    }

    /// The bucket of a calendar date's UTC midnight: days since 1970-01-01; `nil` unless a real `YYYY-MM-DD`.
    public static func day(ofDate text: String) -> Int64? {
        guard WireDeadline.isCalendarDate(text) else { return nil }
        let parts = text.split(separator: "-").compactMap { Int64($0) }
        guard parts.count == 3 else { return nil }
        // Days from the civil date (H. Hinnant's algorithm).
        let year = parts[1] <= 2 ? parts[0] - 1 : parts[0]
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let month = parts[1]
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + parts[2] - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The buckets an occurrence belongs to.
    public static func range(of timing: OccurrenceRow.Timing) -> ClosedRange<Int64> {
        switch timing {
        case .timed(let start, let end, _):
            let first = bucket(ofInstant: start)
            return first...max(first, end > start ? bucket(ofInstant: end - 1) : first)
        case .allDay(let firstDate, let endDate):
            let first = (day(ofDate: firstDate) ?? 0) - 1
            return first...max(first, day(ofDate: endDate) ?? first)
        }
    }

    public static func partition(_ bucket: Int64) -> String { partitionPrefix + String(bucket) }

    /// The bucket of a calendar partition name, or `nil` for another partition.
    public static func bucket(ofPartition name: String) -> Int64? {
        guard name.hasPrefix(partitionPrefix) else { return nil }
        return Int64(name.dropFirst(partitionPrefix.count))
    }
}
