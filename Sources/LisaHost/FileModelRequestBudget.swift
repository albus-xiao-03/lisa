// The persisted daily model-request count (MODEL-01): `<data directory>/model-requests.json` holds the owner's local
// date and the requests reserved on it, so a restart never resets the limit. Only one runtime writes the directory.

import Foundation
import LisaInference
import LisaTime
import Synchronization

/// Counts model requests per local day in a small owner-only file.
public final class FileModelRequestBudget: ModelRequestBudget {
    struct Record: Codable, Hashable {
        static let currentVersion = 1
        var version = currentVersion
        /// `YYYY-MM-DD` in the owner's time zone.
        var day: String
        var count: Int
    }

    /// A count written by another version of Lisa; it is never reset silently.
    struct UnsupportedVersion: Error, CustomStringConvertible {
        var version: Int
        var description: String { "model-requests.json has unsupported version \(version)" }
    }

    public let url: URL
    let clock: any WallClock
    let zone: TimeZone
    private let lock = Mutex(())

    public init(directory: URL, clock: any WallClock, zone: TimeZone) {
        url = directory.appendingPathComponent("model-requests.json")
        self.clock = clock
        self.zone = zone
    }

    public func reserve(limit: Int) throws -> Bool {
        try lock.withLock { _ in
            let today = Self.day(of: clock.now(), in: zone)
            var record = try load()
            if record?.day != today { record = Record(day: today, count: 0) }
            guard var current = record, current.count < limit else { return false }
            current.count += 1
            try save(current)
            return true
        }
    }

    /// The stored record; a missing file means no requests yet. An unreadable file is an error, so the limit can
    /// never be bypassed by damaging it.
    func load() throws -> Record? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: try Data(contentsOf: url))
        guard record.version == Record.currentVersion else { throw UnsupportedVersion(version: record.version) }
        return record
    }

    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func day(of instant: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
