// One planning day as a replica can truthfully show it (plan §8.4.2 "On replicas and in offline planning", §8.4.3
// "What a replica can truthfully show"): its occurrences, each marked verified or not, the sources it can't vouch for,
// and whether it may offer free time at all — never on a day it can't verify.

import LisaSyncProtocol

/// A planning day's occurrences and what may be planned on it.
public struct PlanningDayView: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let listing: OccurrenceListing
        /// `false` for an occurrence whose stored instants were expanded in another zone, or whose source is
        /// zone-unverified for this day: shown with its last-known times, never planned around as certain.
        public let isVerified: Bool

        public init(listing: OccurrenceListing, isVerified: Bool) {
            self.listing = listing
            self.isVerified = isVerified
        }
    }

    /// `YYYY-MM-DD` in the planning zone.
    public let date: String
    public let entries: [Entry]
    /// Sources whose occurrences could move into this day and whose new expansion isn't proved yet.
    public let unverifiedSources: [String]
    /// A bucket of the day is repairing, or not covered.
    public let isStaleOrRepairing: Bool

    public init(date: String, entries: [Entry], unverifiedSources: [String], isStaleOrRepairing: Bool) {
        self.date = date
        self.entries = entries
        self.unverifiedSources = unverifiedSources
        self.isStaleOrRepairing = isStaleOrRepairing
    }

    /// Whether the planner may offer free time on this day: every bucket covered and published, every source and
    /// occurrence verified.
    public var offersFreeTime: Bool {
        !isStaleOrRepairing && unverifiedSources.isEmpty && entries.allSatisfy(\.isVerified)
    }
}
