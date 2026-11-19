// Persisted runtime schedules (OPS-01): next run times and failure counts survive restarts.

import Foundation

/// The schedule of one job, such as a source synchronization.
public struct JobState: Codable, Hashable, Sendable {
    public var nextRunAt: Date
    public var consecutiveFailures: Int
    public var lastRunAt: Date?
    public var lastOutcome: String?

    public init(nextRunAt: Date, consecutiveFailures: Int = 0, lastRunAt: Date? = nil, lastOutcome: String? = nil) {
        self.nextRunAt = nextRunAt
        self.consecutiveFailures = consecutiveFailures
        self.lastRunAt = lastRunAt
        self.lastOutcome = lastOutcome
    }
}

/// Everything the runtime remembers between runs.
public struct RuntimeState: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var jobs: [String: JobState]
    public var lastCycleAt: Date?
    public var lastMaintenanceAt: Date?

    public init() {
        version = RuntimeState.currentVersion
        jobs = [:]
        lastCycleAt = nil
        lastMaintenanceAt = nil
    }
}

/// Stores the runtime state in `<data directory>/runtime-state.json` (owner-only), written atomically.
public final class ScheduleStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("runtime-state.json")
    }

    /// The stored state; an unreadable or newer file yields a fresh state, so jobs simply run again.
    public func load() -> RuntimeState {
        guard let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(RuntimeState.self, from: data),
            state.version == RuntimeState.currentVersion
        else { return RuntimeState() }
        return state
    }

    public func save(_ state: RuntimeState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
