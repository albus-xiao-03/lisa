// A calendar occurrence as Core derives it and replicas receive it (plan §8.4.2, §8.3.5: derived records replicate as
// derived records, outside owner merge): its source, title and timing. A timed occurrence keeps its zone
// classification — `utc`, an IANA zone, `floating`, or `unknown` (a TZID R1 didn't know, resolved like floating) — and,
// when it moves with the zone, the zone it was expanded in and, when retained, its original civil times; an all-day one
// keeps its dates, which every reader turns into instants in the current planning zone.

/// One occurrence row.
public struct OccurrenceRow: Hashable, Sendable {
    public enum Timing: Hashable, Sendable {
        /// [start, end) in UTC milliseconds, end ≥ start; `zone` is `utc`, `floating` or an IANA zone name.
        case timed(start: Int64, end: Int64, zone: String)
        /// Dates `YYYY-MM-DD`, the end exclusive and after the first.
        case allDay(firstDate: String, endDate: String)
    }

    /// The original civil start and end (`YYYY-MM-DDTHH:MM`) of an occurrence that moves with the zone, when retained
    /// (§8.4.2 "Source time evidence"); a migrated row may lack them.
    public struct Civil: Hashable, Sendable {
        public let start: String
        public let end: String

        public init(start: String, end: String) throws(OperationEnvelopeError) {
            for text in [start, end] {
                let parts = text.split(separator: "T", omittingEmptySubsequences: false)
                guard parts.count == 2, WireDeadline.isCalendarDate(String(parts[0])), parts[1].utf8.count == 5,
                    parts[1].utf8.enumerated().allSatisfy({
                        $0.offset == 2 ? $0.element == 0x3A : (0x30...0x39).contains($0.element)
                    })
                else { throw .invalidField("occurrence.civil") }
            }
            self.start = start
            self.end = end
        }
    }

    public let sourceID: String
    public let title: String
    public let timing: Timing
    /// For a floating or unknown-zone occurrence: the planning zone its instants were expanded in.
    public let expandedZone: String?
    public let civil: Civil?

    public init(sourceID: String, title: String, timing: Timing, expandedZone: String? = nil, civil: Civil? = nil)
        throws(OperationEnvelopeError)
    {
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
        if let expandedZone, expandedZone.isEmpty || expandedZone.utf8.count > 64 {
            throw .invalidField("occurrence.expandedZone")
        }
        self.sourceID = sourceID
        self.title = title
        self.timing = timing
        self.expandedZone = expandedZone
        self.civil = civil
    }

    /// Whether its stored instants depend on the planning zone: a floating or unknown-zone timed occurrence.
    public var movesWithZone: Bool {
        if case .timed(_, _, let zone) = timing { zone == "floating" || zone == "unknown" } else { false }
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
            var pairs: [(String, CanonicalValue)] = [
                ("sourceID", .string(sourceID)), ("title", .string(title)), ("timing", timingValue),
            ]
            if let expandedZone { pairs.append(("expandedZone", .string(expandedZone))) }
            if let civil {
                pairs.append(
                    (
                        "civil",
                        .object(try CanonicalObject([("start", .string(civil.start)), ("end", .string(civil.end))]))
                    ))
            }
            return .object(try CanonicalObject(pairs))
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
            let expandedZone = try reader.optionalString("expandedZone")
            var civil: Civil?
            if let object = try reader.optionalObject("civil") {
                var fields = CanonicalFieldReader(object: object)
                civil = try Civil(start: try fields.string("start"), end: try fields.string("end"))
                try fields.finish()
            }
            try reader.finish()
            try self.init(sourceID: sourceID, title: title, timing: decoded, expandedZone: expandedZone, civil: civil)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("occurrence")
        }
    }
}
