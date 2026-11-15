// How each preference key changes the effective owner settings (MEM-01), with strict value validation.

import Foundation
import LisaDomain
import LisaTime

/// Applies preference values to `OwnerSettings`. Keys that configure the host itself (the model endpoint and data
/// sharing) do not map to owner settings; the composition root reads them directly.
public enum PreferenceMapping {
    /// Applies `value` for `key` to `settings`. Returns false for keys that do not map to owner settings.
    @discardableResult
    public static func apply(_ key: PreferenceKey, _ value: PreferenceValue, to settings: inout OwnerSettings) throws
        -> Bool
    {
        switch key {
        case .timeZone:
            guard let zone = TimeZoneID(try text(value, key)) else { throw invalid(key, "is not a known timezone") }
            settings.zone = zone
        case .planningWindows: settings.planning.windows = try windows(value, key)
        case .protectedTime: settings.planning.protectedTime = try windows(value, key)
        case .bufferMinutes: settings.planning.bufferMinutes = try integer(value, key, 0...240)
        case .maximumAllocation:
            let fraction = try number(value, key)
            guard (0.05...1).contains(fraction) else { throw invalid(key, "must be between 0.05 and 1") }
            settings.planning.maximumAllocation = fraction
        case .briefTime: settings.brief.deliveryTime = try time(value, key)
        case .briefLength: settings.brief.targetWords = try integer(value, key, 50...3000)
        case .briefTopics: settings.brief.topics = try list(value, key)
        case .newsInterests: settings.newsInterests = try list(value, key)
        case .mutedSources: settings.mutedSources = try list(value, key)
        case .mutedTopics: settings.mutedTopics = try list(value, key)
        case .reminderOffsets:
            let offsets = try list(value, key).map { item -> Int in
                guard let minutes = Int(item), (1...10_080).contains(minutes) else {
                    throw invalid(key, "must list minutes between 1 and 10080")
                }
                return minutes
            }
            settings.reminders.deadlineOffsetsMinutes = Array(Set(offsets)).sorted(by: >)
        case .reminderChannels:
            let channels = Set(try list(value, key).map { $0.lowercased() })
            let known: Set<String> = ["notification", "email"]
            guard !channels.isEmpty, channels.isSubset(of: known) else {
                throw invalid(key, "must list notification and/or email")
            }
            settings.reminders.emailReminders = channels.contains("email")
            settings.notifications.enabled = channels.contains("notification")
        case .quietHours:
            let window = try windows(value, key)
            guard window.count == 1, window[0].weekdays.count == 7 else {
                throw invalid(key, "must be a single daily HH:MM-HH:MM range")
            }
            settings.reminders.quietHours = QuietHours(start: window[0].start, end: window[0].end)
        case .callEscalation:
            switch value {
            case .flag(let enabled): settings.calls.enabled = enabled
            case .number(let minutes):
                guard minutes.rounded() == minutes, (1...120).contains(minutes) else {
                    throw invalid(key, "must be a whole number of minutes between 1 and 120")
                }
                settings.calls.urgencyWindowMinutes = Int(minutes)
            default: throw invalid(key, "must be true, false or a number of minutes")
            }
        case .ideaExplorationMinutes: settings.planning.defaultIdeaMinutes = try integer(value, key, 5...480)
        case .ideaExplorationFrequency:
            let perWeek = try integer(value, key, 0...21)
            settings.planning.ideaExplorationBudgetMinutes = Int(
                (Double(settings.planning.defaultIdeaMinutes * perWeek) / 7).rounded())
        case .approvedEmailAddresses:
            let addresses = try list(value, key).map { $0.lowercased() }
            guard addresses.allSatisfy(isPlausibleAddress) else { throw invalid(key, "must list email addresses") }
            settings.delivery.approvedEmailAddresses = addresses
        case .approvedPhoneNumber:
            let number = try text(value, key)
            guard number.hasPrefix("+"), number.dropFirst().allSatisfy(\.isNumber), (8...16).contains(number.count)
            else {
                throw invalid(key, "must be an E.164 number such as +15550100")
            }
            settings.calls.approvedNumber = number
        case .emailEnabled: settings.delivery.emailEnabled = try flag(value, key)
        case .callsEnabled: settings.calls.enabled = try flag(value, key)
        case .timeSensitiveNotifications: settings.notifications.timeSensitiveForUrgentDeadlines = try flag(value, key)
        case .modelEndpoint:
            let endpoint = try text(value, key)
            guard let url = URL(string: endpoint),
                url.scheme?.lowercased() == "https" || url.host == "127.0.0.1"
                    || url.host == "localhost"
            else { throw invalid(key, "must be an https address or a loopback address") }
            return false
        case .modelDataSharing:
            let policy = try text(value, key)
            guard ["none", "local-only", "extraction-only", "full"].contains(policy) else {
                throw invalid(key, "must be none, local-only, extraction-only or full")
            }
            return false
        default:
            throw invalid(key, "is not a supported preference")
        }
        return true
    }

    // MARK: - Value parsing

    static func invalid(_ key: PreferenceKey, _ reason: String) -> DomainError {
        .invalidValue(field: key.rawValue, reason: reason)
    }

    static func text(_ value: PreferenceValue, _ key: PreferenceKey) throws -> String {
        guard case .text(let text) = value, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw invalid(key, "must be text")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func number(_ value: PreferenceValue, _ key: PreferenceKey) throws -> Double {
        switch value {
        case .number(let number) where number.isFinite: return number
        case .text(let text): if let number = Double(text), number.isFinite { return number }
        default: break
        }
        throw invalid(key, "must be a number")
    }

    static func integer(_ value: PreferenceValue, _ key: PreferenceKey, _ range: ClosedRange<Int>) throws -> Int {
        let number = try number(value, key)
        guard number.rounded() == number, range.contains(Int(number)) else {
            throw invalid(key, "must be a whole number between \(range.lowerBound) and \(range.upperBound)")
        }
        return Int(number)
    }

    static func flag(_ value: PreferenceValue, _ key: PreferenceKey) throws -> Bool {
        guard case .flag(let flag) = value else { throw invalid(key, "must be true or false") }
        return flag
    }

    static func list(_ value: PreferenceValue, _ key: PreferenceKey) throws -> [String] {
        let items: [String]
        switch value {
        case .list(let values): items = values
        case .text(let text): items = text.split(separator: ",").map(String.init)
        default: throw invalid(key, "must be a list")
        }
        let cleaned = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard cleaned.count <= 50, cleaned.allSatisfy({ $0.count <= 200 }) else {
            throw invalid(key, "must have at most 50 entries of at most 200 characters")
        }
        return cleaned
    }

    static func time(_ value: PreferenceValue, _ key: PreferenceKey) throws -> LocalTime {
        guard let time = LocalTime(iso: try text(value, key)) else {
            throw invalid(key, "must be a time such as 07:30")
        }
        return time
    }

    /// Parses entries such as `09:00-12:00`, `weekdays 09:00-17:00` or `sat,sun 10:00-12:00`.
    static func windows(_ value: PreferenceValue, _ key: PreferenceKey) throws -> [LocalWindow] {
        try list(value, key).map { entry in
            let parts = entry.split(separator: " ").map(String.init)
            guard (1...2).contains(parts.count) else {
                throw invalid(key, "entries must look like 'weekdays 09:00-17:00'")
            }
            let range = parts[parts.count - 1].split(separator: "-").map(String.init)
            guard range.count == 2, let start = LocalTime(iso: range[0]), let end = LocalTime(iso: range[1]),
                start != end
            else { throw invalid(key, "entries must contain a range such as 09:00-17:00") }
            let days = parts.count == 2 ? try weekdays(parts[0], key) : Set(Weekday.allCases)
            return LocalWindow(start: start, end: end, weekdays: days)
        }
    }

    static func weekdays(_ text: String, _ key: PreferenceKey) throws -> Set<Weekday> {
        switch text.lowercased() {
        case "daily": return Set(Weekday.allCases)
        case "weekdays": return [.monday, .tuesday, .wednesday, .thursday, .friday]
        case "weekend": return [.saturday, .sunday]
        default:
            return Set(
                try text.lowercased().split(separator: ",").map { token in
                    guard let day = Weekday.allCases.first(where: { $0.englishNames.contains(String(token)) }) else {
                        throw invalid(key, "unknown weekday \(token)")
                    }
                    return day
                })
        }
    }

    static func isPlausibleAddress(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !address.contains(where: \.isWhitespace)
    }
}
