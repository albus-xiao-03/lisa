// Read-through access for the apps: current data from the host when it answers, otherwise the cached copy and its age.

import Foundation
import LisaAPIContract

/// A value read for the UI, from the host or from the cache.
public struct ReadResult<Value: Sendable>: Sendable {
    /// Where a value came from.
    public enum Source: Hashable, Sendable {
        case host
        case cache
    }

    /// The value read.
    public var value: Value
    /// When the host returned the value.
    public var fetchedAt: Date
    /// Whether the value came from the host or from the cache.
    public var source: Source
    /// Why the host could not be read, when the value came from the cache.
    public var hostError: ClientError?

    /// A value read from `source`, fetched from the host at `fetchedAt`.
    public init(value: Value, fetchedAt: Date, source: Source, hostError: ClientError? = nil) {
        self.value = value
        self.fetchedAt = fetchedAt
        self.source = source
        self.hostError = hostError
    }

    /// How old the value is at `now`; never negative.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(fetchedAt))
    }
}

extension ReadResult: Equatable where Value: Equatable {}

extension ReadResult: Hashable where Value: Hashable {}

/// Reads the brief, the rundown and the task list through the response cache (UI-03, plan §6.6).
///
/// - When the host answers, the value is cached and returned from the host.
/// - When the host cannot be reached or asks the client to retry later, the cached value is returned with its fetch
///   time and the host's error. Without a cached value, the error is thrown.
/// - When the device is not paired or the host removed it (401), the cache is cleared before the error is thrown, so a
///   removed device stops showing the owner's data (plan §6.3).
/// - Other errors are thrown unchanged. A cache that cannot be written never fails a read the host answered.
public struct CachedReader: Sendable {
    /// The client that reads the host.
    public let client: LisaAPIClient
    /// The cache that keeps the latest values.
    public let cache: ResponseCache
    private let timeZone: TimeZone
    private let clock: @Sendable () -> Date

    /// - Parameters:
    ///   - timeZone: the zone of the device's current date, used when no date is given and the host cannot say which
    ///     date is current: the cached value of the latest date on or before it is returned.
    ///   - clock: the time recorded as a value's fetch time.
    public init(
        client: LisaAPIClient, cache: ResponseCache, timeZone: TimeZone = .current,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.cache = cache
        self.timeZone = timeZone
        self.clock = clock
    }

    /// The brief of `date` (`YYYY-MM-DD`), or of the host's current date.
    public func brief(date: String? = nil) async throws(ClientError) -> ReadResult<BriefDTO> {
        let client = client
        let cache = cache
        let today = currentLocalDate()
        return try await read(
            fetch: { () async throws(ClientError) -> BriefDTO in try await client.brief(date: date) },
            store: { brief, fetchedAt in try await cache.store(brief, fetchedAt: fetchedAt) },
            cached: {
                if let date { return try await cache.brief(for: date) }
                return try await cache.latestBrief(onOrBefore: today)
            })
    }

    /// The rundown of `date` (`YYYY-MM-DD`), or of the host's current date.
    public func rundown(date: String? = nil) async throws(ClientError) -> ReadResult<RundownDTO> {
        let client = client
        let cache = cache
        let today = currentLocalDate()
        return try await read(
            fetch: { () async throws(ClientError) -> RundownDTO in try await client.rundown(date: date) },
            store: { rundown, fetchedAt in try await cache.store(rundown, fetchedAt: fetchedAt) },
            cached: {
                if let date { return try await cache.rundown(for: date) }
                return try await cache.latestRundown(onOrBefore: today)
            })
    }

    /// The first page of the task list, optionally only tasks with `status`.
    public func tasks(status: TaskStatusValue? = nil) async throws(ClientError) -> ReadResult<Page<TaskDTO>> {
        let client = client
        let cache = cache
        return try await read(
            fetch: { () async throws(ClientError) -> Page<TaskDTO> in try await client.tasks(status: status) },
            store: { page, fetchedAt in try await cache.store(page, status: status, fetchedAt: fetchedAt) },
            cached: { try await cache.tasks(status: status) })
    }

    private func read<Value: Codable & Sendable>(
        fetch: () async throws(ClientError) -> Value,
        store: (Value, Date) async throws -> Void,
        cached: () async throws -> CachedValue<Value>?
    ) async throws(ClientError) -> ReadResult<Value> {
        do throws(ClientError) {
            let value = try await fetch()
            let fetchedAt = clock()
            try? await store(value, fetchedAt)
            return ReadResult(value: value, fetchedAt: fetchedAt, source: .host)
        } catch {
            if error == .notPaired || error.isUnauthenticated {
                try? await cache.clear()
                throw error
            }
            guard error.isHostUnavailable, let copy = try? await cached() else { throw error }
            return ReadResult(value: copy.value, fetchedAt: copy.fetchedAt, source: .cache, hostError: error)
        }
    }

    /// The device's current local date (`YYYY-MM-DD`): the best guess for the host's current date while the host
    /// cannot be asked.
    private func currentLocalDate() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: clock())
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
