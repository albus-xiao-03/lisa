// A calendar occurrence as Core derives it and replicas receive it (plan §8.4.2, §8.3.5: derived records replicate as
// derived records, outside owner merge): its source, title and timing. A timed occurrence keeps its zone
// classification (`utc`, `floating`, or an IANA zone) for re-expansion when the planning zone changes; an all-day one
// keeps its dates, which every reader turns into instants in the current planning zone.

/// One occurrence row.
public struct OccurrenceRow: Hashable, Sendable {
    public enum Timing: Hashable, Sendable {
        /// [start, end) in UTC milliseconds, end ≥ start; `zone` is `utc`, `floating` or an IANA zone name.
        case timed(start: Int64, end: Int64, zone: String)
        /// Dates `YYYY-MM-DD`, the end exclusive and after the first.
        case allDay(firstDate: String, endDate: String)
    }

    public let sourceID: String
    public let title: String
    public let timing: Timing

    public init(sourceID: String, title: String, timing: Timing) throws(OperationEnvelopeError) {
        guard !sourceID.isEmpty, sourceID.utf8.count <= 128 else { throw .invalidField("occurrence.sourceID") }
        guard title.count <= 1_000 else { throw .invalidField("occurrence.title") }
        switch timing {
        case .timed(let start, let end, let zone):
            guard end >= start, !zone.isEmpty, zone.utf8.count <= 64 else { throw .invalidField("occurrence.timing") }
        case .allDay(let firstDate, let endDate):
            guard let first = CalendarBuckets.day(ofDate: firstDate), let end = CalendarBuckets.day(ofDate: endDate),
                end > first
            else { throw .invalidField("occurrence.timing") }
        }
        self.sourceID = sourceID
        self.title = title
        self.timing = timing
    }

    /// The buckets the occurrence belongs to.
    public var buckets: ClosedRange<Int64> { CalendarBuckets.range(of: timing) }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            let timingValue: CanonicalValue
            switch timing {
            case .timed(let start, let end, let zone):
                timingValue = .object(
                    try CanonicalObject([
                        ("kind", .string("timed")), ("start", .integer(start)), ("end", .integer(end)),
                        ("zone", .string(zone)),
                    ]))
            case .allDay(let firstDate, let endDate):
                timingValue = .object(
                    try CanonicalObject([
                        ("kind", .string("allDay")), ("firstDate", .string(firstDate)), ("endDate", .string(endDate)),
                    ]))
            }
            return .object(
                try CanonicalObject([
                    ("sourceID", .string(sourceID)), ("title", .string(title)), ("timing", timingValue),
                ]))
        }
    }

    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            var timing = CanonicalFieldReader(object: try reader.object("timing"))
            let decoded: Timing
            switch try timing.string("kind") {
            case "timed":
                decoded = .timed(
                    start: try timing.integer("start"), end: try timing.integer("end"), zone: try timing.string("zone"))
            case "allDay":
                decoded = .allDay(firstDate: try timing.string("firstDate"), endDate: try timing.string("endDate"))
            default:
                throw OperationEnvelopeError.invalidField("occurrence.timing")
            }
            try timing.finish()
            let sourceID = try reader.string("sourceID")
            let title = try reader.string("title")
            try reader.finish()
            try self.init(sourceID: sourceID, title: title, timing: decoded)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("occurrence")
        }
    }
}
