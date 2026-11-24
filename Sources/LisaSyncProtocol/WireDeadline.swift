// A deadline on the wire (plan §8.2.3; R1's `Deadline`, `Sources/LisaTime/Deadline.swift`): an exact instant in UTC
// milliseconds with the zone it was given in, or a date with no time of day, which never becomes an invented time.

/// A task or idea deadline in an operation payload.
public enum WireDeadline: Hashable, Sendable {
    /// Due at an exact instant; `zone` is the IANA zone it was given in, when known.
    case instant(unixMilliseconds: Int64, zone: String?)
    /// Due on a local calendar date `YYYY-MM-DD`, with no time of day.
    case date(String)

    /// The longest zone name accepted.
    public static let maximumZoneBytes = 64

    /// Checks the form: a real calendar date, or a zone name of IANA characters.
    public init(validating deadline: WireDeadline) throws(OperationEnvelopeError) {
        switch deadline {
        case .instant(_, let zone):
            if let zone {
                guard !zone.isEmpty, zone.utf8.count <= Self.maximumZoneBytes,
                    zone.unicodeScalars.allSatisfy({ Self.zoneScalars.contains($0) })
                else { throw .invalidField("payload.deadline.zone") }
            }
        case .date(let text):
            guard Self.isCalendarDate(text) else { throw .invalidField("payload.deadline.date") }
        }
        self = deadline
    }

    /// `{"kind":"instant","at":…,"zone"?:…}` or `{"kind":"date","date":"YYYY-MM-DD"}`.
    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .instant(let at, let zone):
                var pairs: [(String, CanonicalValue)] = [("kind", .string("instant")), ("at", .integer(at))]
                if let zone { pairs.append(("zone", .string(zone))) }
                return .object(try CanonicalObject(pairs))
            case .date(let date):
                return .object(try CanonicalObject([("kind", .string("date")), ("date", .string(date))]))
            }
        }
    }

    /// Reads the canonical form strictly.
    public init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(value)
            let deadline: WireDeadline
            switch try reader.string("kind") {
            case "instant":
                deadline = .instant(unixMilliseconds: try reader.integer("at"), zone: try reader.optionalString("zone"))
            case "date":
                deadline = .date(try reader.string("date"))
            default:
                throw OperationEnvelopeError.invalidField("payload.deadline.kind")
            }
            try reader.finish()
            try self.init(validating: deadline)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("payload.deadline")
        }
    }

    private static let zoneScalars = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/_+-".unicodeScalars)

    /// `YYYY-MM-DD` naming a day that exists in the proleptic Gregorian calendar, years 0001–9999.
    static func isCalendarDate(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D else { return false }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for byte in bytes[range] {
                guard (0x30...0x39).contains(byte) else { return nil }
                value = value * 10 + Int(byte - 0x30)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10), year >= 1,
            (1...12).contains(month)
        else { return false }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        return (1...days).contains(day)
    }
}
