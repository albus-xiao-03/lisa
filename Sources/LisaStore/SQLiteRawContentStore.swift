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

    public func purge(storedBefore cutoff: Date) throws -> Int {
        try database.perform { session in
            try session.query(
                "DELETE FROM raw_content WHERE stored_at < ?",
                [.integer(Int64((cutoff.timeIntervalSince1970 * 1000).rounded()))])
            return session.changes
        }
    }
}
