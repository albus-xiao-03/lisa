// A cached response with the time it was fetched, so the UI can show its age (UI-03).

import Foundation

/// A cached value and when the host returned it.
public struct CachedValue<Value: Codable & Sendable>: Codable, Sendable {
    /// The cached value.
    public var value: Value
    /// When the host returned the value.
    public var fetchedAt: Date

    /// A value the host returned at `fetchedAt`.
    public init(value: Value, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }

    /// How old the value is at `now`; never negative.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(fetchedAt))
    }
}

extension CachedValue: Equatable where Value: Equatable {}

extension CachedValue: Hashable where Value: Hashable {}
