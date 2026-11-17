// The rundown as plain spoken sentences: the planned blocks with their start times, what could not be scheduled, and
// a notice when the rundown is a saved copy.

import Foundation
import LisaAPIContract
import LisaClient

/// What Siri says for "get today's rundown" (SIRI-01). A saved copy, read while the host is unreachable, starts with
/// its day and age, so it is never read out as current (UI-03).
public enum RundownSpeech {
    /// The most blocks read out; the rest are counted.
    public static let maxSpokenBlocks = 8
    /// The block states that are still part of the plan.
    static let plannedStates: Set<String> = ["proposed", "accepted", "locked"]

    /// The rundown in `result` as sentences.
    ///
    /// - Parameters:
    ///   - result: the rundown read, from the host or the cache.
    ///   - now: the current time, for the age of a saved copy.
    ///   - isEarlierDay: whether it is a saved copy of an earlier day than the device's.
    ///   - timeZone: the device's zone; block times use the rundown's own zone when it is valid.
    ///   - locale: the device's time format.
    public static func text(
        for result: ReadResult<RundownDTO>, at now: Date, isEarlierDay: Bool, timeZone: TimeZone, locale: Locale
    ) -> String {
        let rundown = result.value
        let day = LocalDay.spokenEnglish(rundown.date)
        var sentences: [String] = []
        if result.source == .cache || isEarlierDay {
            sentences.append(
                "This is the saved rundown for \(day), from \(AgePhrase.english(result.age(at: now))) ago. It may be "
                    + "out of date.")
        }
        let isToday = rundown.date == LocalDay.string(for: now, in: timeZone)
        let dayName = isToday ? "today" : day
        let zone = TimeZone(identifier: rundown.zone) ?? timeZone
        let planned = rundown.blocks.filter { plannedStates.contains($0.state) }.sorted { $0.start < $1.start }
        if planned.isEmpty {
            sentences.append("Nothing is planned for \(dayName).")
        } else {
            sentences.append("Here is your plan for \(dayName).")
            for block in planned.prefix(maxSpokenBlocks) {
                let time = SpokenMoment.time(block.start, in: zone, locale: locale)
                let title = spokenTitle(block.title)
                sentences.append(
                    block.state == "proposed" ? "At \(time), suggested: \(title)." : "At \(time), \(title).")
            }
            if planned.count > maxSpokenBlocks {
                sentences.append(count(planned.count - maxSpokenBlocks, "more block", "more blocks") + " after that.")
            }
        }
        if !rundown.unscheduled.isEmpty {
            sentences.append(count(rundown.unscheduled.count, "item", "items") + " couldn't be scheduled.")
        }
        if rundown.availabilityUncertain {
            sentences.append("Some calendar information is missing, so times may change.")
        }
        return sentences.joined(separator: " ")
    }

    /// A title without markup and without a closing period, to be read inside a sentence.
    private static func spokenTitle(_ title: String) -> String {
        var text = SpokenText.plain(title)
        while let last = text.last, last == "." || last == "," || last == ";" || last == ":" { text.removeLast() }
        return text.isEmpty ? "an untitled block" : text
    }

    private static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(plural)"
    }
}
