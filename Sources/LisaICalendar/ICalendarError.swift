// Errors that make a calendar unusable as a whole; per-event problems are warnings instead.

/// A failure that prevents parsing the calendar. A failed parse never counts as an empty calendar.
public enum ICalendarError: Error, Hashable, Sendable, CustomStringConvertible {
    case inputTooLarge
    case lineTooLong
    case tooManyLines
    case nestingTooDeep
    case unbalancedComponents(String)
    case notACalendar
    case notUTF8

    public var description: String {
        switch self {
        case .inputTooLarge: "the calendar exceeds the configured size limit"
        case .lineTooLong: "a calendar line exceeds the configured length limit"
        case .tooManyLines: "the calendar has more lines than the configured limit"
        case .nestingTooDeep: "calendar components are nested too deeply"
        case .unbalancedComponents(let name): "component \(name) is not properly closed"
        case .notACalendar: "the data is not an iCalendar object (no VCALENDAR)"
        case .notUTF8: "the calendar is not valid UTF-8 text"
        }
    }
}
