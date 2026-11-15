// Parses written times of day such as "3pm", "15:30" and "noon".

import Foundation

/// Parses written times of day. Unrecognized text yields `nil` rather than a guessed time.
public enum TimeOfDayParser {
    /// Parses forms such as `15:30`, `3:30 pm`, `3pm`, `9 am`, `noon` and `midnight`.
    public static func parse(_ text: String) -> LocalTime? {
        var value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["at ", "by ", "around "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        value = value.replacingOccurrences(of: ".", with: "")
        switch value {
        case "noon", "midday": return LocalTime(hour: 12, minute: 0)
        case "midnight": return LocalTime.midnight
        default: break
        }
        var meridiem: String?
        for marker in ["am", "pm"] where value.hasSuffix(marker) {
            meridiem = marker
            value = String(value.dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
            parts[0].count <= 2, let rawHour = Int(parts[0])
        else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, parts.count == 1 || parts[1].count == 2 else { return nil }
        var hour = rawHour
        switch meridiem {
        case "am":
            guard (1...12).contains(hour) else { return nil }
            hour = hour == 12 ? 0 : hour
        case "pm":
            guard (1...12).contains(hour) else { return nil }
            hour = hour == 12 ? 12 : hour + 12
        default:
            guard parts.count == 2 else { return nil }
        }
        return LocalTime(hour: hour, minute: minute)
    }
}
