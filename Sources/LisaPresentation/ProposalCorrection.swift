// Corrections the owner makes to an event proposal in the inbox: its title, its timing or its place.

import Foundation
import LisaAPIContract

/// Corrections to an event proposal's details (EVENT-01: the owner corrects a proposal). Fields left `nil` stay
/// unchanged on the host. Correcting a proposal that needed clarification with a date makes it reviewable against the
/// calendars.
public struct ProposalCorrection: Hashable, Sendable {
    /// A new title.
    public var title: String?
    /// New timing: a start (with an optional end and zone), or a date (`YYYY-MM-DD`) for an all-day event.
    public var timing: ProposedTimingDTO?
    /// A new place.
    public var location: String?

    /// A correction setting the given fields.
    public init(title: String? = nil, timing: ProposedTimingDTO? = nil, location: String? = nil) {
        self.title = title
        self.timing = timing
        self.location = location
    }

    /// Whether the correction changes nothing.
    public var isEmpty: Bool { title == nil && timing == nil && location == nil }

    /// Why the correction cannot be sent, or `nil` when it can.
    public var problem: String? {
        if isEmpty { return "Nothing was changed." }
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "An event needs a title." }
        if let timing {
            if timing.isUnknown { return "Give the event a start time or a date." }
            if timing.start != nil, timing.date != nil { return "Choose either a start time or a date, not both." }
            if let start = timing.start, let end = timing.end, end < start { return "The end is before the start." }
            if timing.start == nil, timing.end != nil { return "An end time needs a start time." }
            if let date = timing.date, !APIDates.isLocalDate(date) { return "The date is not a valid calendar date." }
            if let zone = timing.zone, TimeZone(identifier: zone) == nil { return "The time zone is not known." }
        }
        return nil
    }

    /// The proposal action for a proposal the owner last saw at `expectedRevision`.
    func request(expectedRevision: Int64) -> ProposalActionRequest {
        ProposalActionRequest(
            action: .correct, expectedRevision: expectedRevision,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines), timing: timing,
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
