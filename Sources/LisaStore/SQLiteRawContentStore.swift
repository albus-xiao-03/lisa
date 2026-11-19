// Raw source content in its own table, so retention can purge it without touching records.

import Foundation
import LisaPorts
import LisaSQLite

/// The SQLite implementation of RawContentStore.
public final class SQLiteRawContentStore: RawContentStore {
    let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    public func put(_ data: Data, kind: String, now: Date) throws -> RawContentRef {
        let ref = RawContentRef("raw-\(UUID().uuidString.lowercased())")
        try database.perform { session in
            try session.query(
                "INSERT INTO raw_content (id, kind, stored_at, size, data) VALUES (?, ?, ?, ?, ?)",
                [
                    .text(ref.value), .text(kind), .integer(Int64((now.timeIntervalSince1970 * 1000).rounded())),
                    .integer(Int64(data.count)), .blob(data),
                ])
        }
        return ref
    }

    public func get(_ ref: RawContentRef) throws -> Data? {
        try database.perform { session in
            try session.query("SELECT data FROM raw_content WHERE id = ?", [.text(ref.value)]).first?.first?.blob
        }
    }

    public func delete(_ ref: RawContentRef) throws {
        try database.perform { session in
            try session.query("DELETE FROM raw_content WHERE id = ?", [.text(ref.value)])
        }
    }

    public func purge(keepingAtMostBytes budget: Int) throws -> Int {
        try database.writeTransaction { session in
            let total = try session.query("SELECT COALESCE(SUM(size), 0) FROM raw_content").first?.first?.integer ?? 0
            var excess = total - Int64(max(0, budget))
            guard excess > 0 else { return 0 }
            var oldest: [String] = []
            for row in try session.query("SELECT id, size FROM raw_content ORDER BY stored_at ASC, id ASC") {
                guard excess > 0, let id = row[0].text, let size = row[1].integer else { break }
                oldest.append(id)
                excess -= size
            }
            for id in oldest { try session.query("DELETE FROM raw_content WHERE id = ?", [.text(id)]) }
            return oldest.count
        }
    }

    public func purge(storedBefore cutoff: Date) throws -> Int {
        try database.perform { session in
            try session.query(
                "DELETE FROM raw_content WHERE stored_at < ?",
                [.integer(Int64((cutoff.timeIntervalSince1970 * 1000).rounded()))])
            return session.changes
        }
    }
}
