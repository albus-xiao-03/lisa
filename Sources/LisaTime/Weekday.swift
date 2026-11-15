// Days of the week, numbered as in ISO 8601 (Monday is 1) and named as in iCalendar.

/// A day of the week. Raw values follow ISO 8601: Monday is 1 and Sunday is 7.
public enum Weekday: Int, CaseIterable, Codable, Sendable, Comparable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The two-letter iCalendar code, such as `MO`.
    public var iCalendarCode: String {
        switch self {
        case .monday: "MO"
        case .tuesday: "TU"
        case .wednesday: "WE"
        case .thursday: "TH"
        case .friday: "FR"
        case .saturday: "SA"
        case .sunday: "SU"
        }
    }

    /// Parses a two-letter iCalendar code, ignoring case.
    public init?(iCalendarCode code: String) {
        guard let match = Weekday.allCases.first(where: { $0.iCalendarCode == code.uppercased() }) else {
            return nil
        }
        self = match
    }

    /// English names accepted in spoken or written dates, such as "monday" and "mon".
    public var englishNames: [String] {
        switch self {
        case .monday: ["monday", "mon"]
        case .tuesday: ["tuesday", "tue", "tues"]
        case .wednesday: ["wednesday", "wed"]
        case .thursday: ["thursday", "thu", "thur", "thurs"]
        case .friday: ["friday", "fri"]
        case .saturday: ["saturday", "sat"]
        case .sunday: ["sunday", "sun"]
        }
    }

    /// The English display name, such as "Monday".
    public var displayName: String {
        let name = englishNames[0]
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
