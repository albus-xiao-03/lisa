// How the app names and groups the host's preference keys, and how it shows and reads their values; keys the app does
// not know are shown by their own name.

import Foundation
import LisaAPIContract

/// How the memory and settings screens present one preference key (MEM-01): a readable title, the form of its value
/// and the group it belongs to. The host owns the keys and checks every value; a key the app does not know is shown
/// by its own name, as text, in `Group.other`.
public struct PreferenceDescriptor: Hashable, Sendable {
    /// The form of a preference's value, which picks the editor.
    public enum ValueKind: Hashable, Sendable {
        /// Text, such as a time zone or a time like `07:30`.
        case text
        /// A number.
        case number
        /// On or off.
        case flag
        /// A list of entries, such as topics or planning windows like `weekdays 09:00-17:00`.
        case list
    }

    /// Where a preference belongs on the screens.
    public enum Group: String, Hashable, Sendable, CaseIterable {
        case general
        case planning
        case brief
        case news
        case reminders
        /// Who Lisa may contact and how: recipients, channels, calls and notification urgency. The settings screen
        /// shows these with the delivery modes.
        case delivery
        case ideas
        case model
        /// Keys the app does not know.
        case other

        /// A heading for the group.
        public var title: String {
            switch self {
            case .general: "General"
            case .planning: "Planning"
            case .brief: "Brief"
            case .news: "News"
            case .reminders: "Reminders"
            case .delivery: "Delivery"
            case .ideas: "Ideas"
            case .model: "Model"
            case .other: "Other"
            }
        }
    }

    /// The host's key, such as `brief.time`.
    public var key: String
    /// A readable title, such as "Brief time".
    public var title: String
    /// The form of the value.
    public var kind: ValueKind
    /// Where the preference belongs.
    public var group: Group
    /// A short hint about accepted values, such as "A time such as 07:30".
    public var hint: String?

    /// A descriptor of `key`.
    public init(key: String, title: String, kind: ValueKind, group: Group, hint: String? = nil) {
        self.key = key
        self.title = title
        self.kind = kind
        self.group = group
        self.hint = hint
    }

    /// The descriptor of `key`: a known one, or the key's own name as text in `Group.other`.
    public static func describing(_ key: String) -> PreferenceDescriptor {
        known.first { $0.key == key } ?? PreferenceDescriptor(key: key, title: key, kind: .text, group: .other)
    }

    /// The keys the host supports in this release (MEM-01), in screen order.
    public static let known: [PreferenceDescriptor] = [
        .init(key: "timeZone", title: "Time zone", kind: .text, group: .general, hint: "Such as Europe/Berlin"),
        .init(
            key: "planning.windows", title: "Planning windows", kind: .list, group: .planning,
            hint: "Such as weekdays 09:00-17:00"),
        .init(
            key: "planning.protectedTime", title: "Protected time", kind: .list, group: .planning,
            hint: "Such as daily 12:00-13:00"),
        .init(
            key: "planning.bufferMinutes", title: "Buffer between blocks (minutes)", kind: .number, group: .planning,
            hint: "0 to 240"),
        .init(
            key: "planning.maximumAllocation", title: "Share of free time to plan", kind: .number, group: .planning,
            hint: "0.05 to 1"),
        .init(key: "brief.time", title: "Brief time", kind: .text, group: .brief, hint: "A time such as 07:30"),
        .init(
            key: "brief.targetWords", title: "Brief length (words)", kind: .number, group: .brief, hint: "50 to 3000"),
        .init(key: "brief.topics", title: "Brief topics", kind: .list, group: .brief),
        .init(key: "news.interests", title: "News interests", kind: .list, group: .news),
        .init(key: "news.mutedSources", title: "Muted news sources", kind: .list, group: .news),
        .init(key: "news.mutedTopics", title: "Muted news topics", kind: .list, group: .news),
        .init(
            key: "reminders.deadlineOffsetsMinutes", title: "Deadline reminders (minutes before)", kind: .list,
            group: .reminders, hint: "Such as 1440, 60"),
        .init(
            key: "reminders.channels", title: "Reminder channels", kind: .list, group: .delivery,
            hint: "notification, email or both"),
        .init(key: "quietHours", title: "Quiet hours", kind: .text, group: .delivery, hint: "Such as 22:00-07:00"),
        .init(
            key: "calls.escalation", title: "Call escalation", kind: .flag, group: .delivery,
            hint: "On, off, or the minutes before a deadline"),
        .init(
            key: "delivery.approvedEmailAddresses", title: "Approved email recipients", kind: .list, group: .delivery),
        .init(
            key: "delivery.approvedPhoneNumber", title: "Approved phone number", kind: .text, group: .delivery,
            hint: "Such as +15550100"),
        .init(key: "delivery.emailEnabled", title: "Email delivery", kind: .flag, group: .delivery),
        .init(key: "delivery.callsEnabled", title: "Phone calls", kind: .flag, group: .delivery),
        .init(
            key: "notifications.timeSensitive", title: "Time Sensitive notifications for urgent deadlines", kind: .flag,
            group: .delivery),
        .init(
            key: "ideas.explorationMinutes", title: "Idea exploration length (minutes)", kind: .number, group: .ideas,
            hint: "5 to 480"),
        .init(
            key: "ideas.explorationPerWeek", title: "Idea explorations per week", kind: .number, group: .ideas,
            hint: "0 to 21"),
        .init(key: "model.endpoint", title: "Model endpoint", kind: .text, group: .model),
        .init(
            key: "model.dataSharing", title: "Model data sharing", kind: .text, group: .model,
            hint: "none, localOnly or remoteMinimized"),
    ]

    /// `value` as short text for a row: on or off, a number without a needless fraction, or the entries joined by
    /// commas.
    public static func displayText(_ value: PreferenceValueDTO) -> String {
        switch value {
        case .text(let text): text
        case .flag(let flag): flag ? "On" : "Off"
        case .list(let items): items.joined(separator: ", ")
        case .number(let number):
            number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        }
    }

    /// The value the owner typed as `text`, in the form of `kind`: entries separated by commas or new lines for a
    /// list, a number, on or off (also yes or no, true or false), or the trimmed text. `nil` when the text is empty or
    /// not of that form. The host checks the value itself.
    public static func value(fromText text: String, as kind: ValueKind) -> PreferenceValueDTO? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch kind {
        case .text:
            return .text(trimmed)
        case .number:
            guard let number = Double(trimmed), number.isFinite else { return nil }
            return .number(number)
        case .flag:
            switch trimmed.lowercased() {
            case "on", "yes", "true": return .flag(true)
            case "off", "no", "false": return .flag(false)
            default: return nil
            }
        case .list:
            let items = trimmed.split { $0 == "," || $0.isNewline }.map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            return items.isEmpty ? nil : .list(items)
        }
    }
}
