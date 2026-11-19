// What the device has cached for outages: which brief, rundown or task list, of which date, fetched when.

import Foundation
import LisaClient

/// One kind of cached data and its age, for the connectivity screen (UI-02: viewing cached-data age).
public struct CachedDataSummary: Hashable, Sendable {
    /// What is cached: the brief, the rundown or the task list.
    public var kind: CacheKey.Kind
    /// The local date (`YYYY-MM-DD`) of a cached brief or rundown.
    public var localDate: String?
    /// When the host returned it.
    public var fetchedAt: Date

    /// A summary of cached data of `kind`.
    public init(kind: CacheKey.Kind, localDate: String?, fetchedAt: Date) {
        self.kind = kind
        self.localDate = localDate
        self.fetchedAt = fetchedAt
    }

    /// How old it is at `now`; never negative.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(fetchedAt))
    }
}
