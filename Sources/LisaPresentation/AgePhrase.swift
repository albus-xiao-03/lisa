// How old saved data is, in plain English words for speech and labels ("3 hours").

import Foundation

/// Describes an age in words, such as "less than a minute", "5 minutes", "2 hours" or "3 days".
public enum AgePhrase {
    /// `seconds` in the largest whole unit; negative ages count as zero.
    public static func english(_ seconds: TimeInterval) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "less than a minute" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return count(minutes, "minute") }
        let hours = minutes / 60
        if hours < 48 { return count(hours, "hour") }
        return count(hours / 24, "day")
    }

    private static func count(_ value: Int, _ unit: String) -> String {
        value == 1 ? "1 \(unit)" : "\(value) \(unit)s"
    }
}
