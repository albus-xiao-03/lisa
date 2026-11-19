// The response cache (UI-03): the latest brief and rundown per local date and the task list, with their fetch times.

import Foundation
import LisaAPIContract

/// Keeps the latest brief and rundown of each recent local date, and the first page of the task list, so the apps can
/// show them with their age while the host is unreachable (UI-03, plan §6.6).
///
/// A cached value that cannot be decoded, for example after an update changed its format, is removed and treated as
/// missing.
public actor ResponseCache {
    private static let currentVersion = 1

    private let storage: any ResponseCacheStorage
    private let retainedDates: Int

    /// - Parameter retainedDates: how many of the most recent local dates keep their cached brief and rundown.
    public init(storage: any ResponseCacheStorage, retainedDates: Int = 14) {
        self.storage = storage
        self.retainedDates = max(1, retainedDates)
    }

    /// The cached brief of `date` (`YYYY-MM-DD`).
    public func brief(for date: String) throws -> CachedValue<BriefDTO>? {
        guard let key = CacheKey.brief(date: date) else { return nil }
        return try value(BriefDTO.self, for: key)
    }

    /// The cached brief of the latest date, or of the latest date on or before `date`.
    public func latestBrief(onOrBefore date: String? = nil) throws -> CachedValue<BriefDTO>? {
        try latest(BriefDTO.self, kind: .brief, onOrBefore: date)
    }

    /// The cached rundown of `date` (`YYYY-MM-DD`).
    public func rundown(for date: String) throws -> CachedValue<RundownDTO>? {
        guard let key = CacheKey.rundown(date: date) else { return nil }
        return try value(RundownDTO.self, for: key)
    }

    /// The cached rundown of the latest date, or of the latest date on or before `date`.
    public func latestRundown(onOrBefore date: String? = nil) throws -> CachedValue<RundownDTO>? {
        try latest(RundownDTO.self, kind: .rundown, onOrBefore: date)
    }

    /// The cached first page of the task list with this status filter.
    public func tasks(status: TaskStatusValue? = nil) throws -> CachedValue<Page<TaskDTO>>? {
        try value(Page<TaskDTO>.self, for: .tasks(status: status))
    }

    /// Caches `brief` under its own date, and drops the briefs of dates older than the retained ones.
    ///
    /// - Returns: `false`, caching nothing, when the brief's date is not a `YYYY-MM-DD` calendar date.
    @discardableResult
    public func store(_ brief: BriefDTO, fetchedAt: Date) throws -> Bool {
        guard let key = CacheKey.brief(date: brief.date) else { return false }
        try store(brief, for: key, fetchedAt: fetchedAt)
        try prune(.brief)
        return true
    }

    /// Caches `rundown` under its own date, and drops the rundowns of dates older than the retained ones.
    ///
    /// - Returns: `false`, caching nothing, when the rundown's date is not a `YYYY-MM-DD` calendar date.
    @discardableResult
    public func store(_ rundown: RundownDTO, fetchedAt: Date) throws -> Bool {
        guard let key = CacheKey.rundown(date: rundown.date) else { return false }
        try store(rundown, for: key, fetchedAt: fetchedAt)
        try prune(.rundown)
        return true
    }

    /// Caches the first page of the task list with this status filter.
    public func store(_ tasks: Page<TaskDTO>, status: TaskStatusValue?, fetchedAt: Date) throws {
        try store(tasks, for: .tasks(status: status), fetchedAt: fetchedAt)
    }

    /// Removes every cached value, for example after the host removed this device (plan §6.3).
    public func clear() throws {
        try storage.removeAll()
    }

    // MARK: - Stored form

    private struct Envelope<Value: Codable & Sendable>: Codable {
        var version: Int
        var fetchedAt: Date
        var value: Value
    }

    private func value<Value: Codable & Sendable>(_ type: Value.Type, for key: CacheKey) throws -> CachedValue<Value>? {
        guard let data = try storage.read(key) else { return nil }
        guard let envelope = try? StorageCoding.decoder().decode(Envelope<Value>.self, from: data),
            envelope.version == Self.currentVersion
        else {
            try storage.remove(key)
            return nil
        }
        return CachedValue(value: envelope.value, fetchedAt: envelope.fetchedAt)
    }

    private func store<Value: Codable & Sendable>(_ value: Value, for key: CacheKey, fetchedAt: Date) throws {
        let envelope = Envelope(version: Self.currentVersion, fetchedAt: fetchedAt, value: value)
        try storage.write(try StorageCoding.encoder().encode(envelope), for: key)
    }

    /// The dated keys of `kind`, latest date first.
    private func datedKeys(_ kind: CacheKey.Kind) throws -> [CacheKey] {
        try storage.keys().filter { $0.kind == kind }.sorted { ($0.qualifier ?? "") > ($1.qualifier ?? "") }
    }

    private func latest<Value: Codable & Sendable>(
        _ type: Value.Type, kind: CacheKey.Kind, onOrBefore date: String?
    ) throws -> CachedValue<Value>? {
        for key in try datedKeys(kind) where date.map({ (key.qualifier ?? "") <= $0 }) ?? true {
            if let cached = try value(type, for: key) { return cached }
        }
        return nil
    }

    private func prune(_ kind: CacheKey.Kind) throws {
        for key in try datedKeys(kind).dropFirst(retainedDates) {
            try storage.remove(key)
        }
    }
}
