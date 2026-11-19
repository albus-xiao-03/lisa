// Opens the database: protective pragmas, owner-only file permissions, migrations and a schema check.

import Foundation
import LisaPorts
import LisaSQLite

/// The opened store: records, raw content and maintenance on one serialized connection.
public final class LisaStorage: Sendable {
    public let records: SQLiteRecordStore
    public let rawContent: SQLiteRawContentStore
    public let maintenance: SQLiteStoreMaintenance
    public let migration: MigrationReport
    public let path: String

    /// Opens or creates the database at `path` and migrates it to the newest schema.
    ///
    /// A failed migration leaves the previous data in place (and a pre-migration copy beside it); the database is never
    /// recreated or discarded.
    public static func open(path: String, now: Date, migrations: [Migration] = Migrations.all) throws -> LisaStorage {
        let isNew = !FileManager.default.fileExists(atPath: path)
        let database = try SQLiteDatabase(path: path)
        if isNew { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        try database.perform { session in
            try session.query("PRAGMA journal_mode = WAL")
            try session.execute("PRAGMA synchronous = FULL")
            try session.execute("PRAGMA foreign_keys = ON")
            try session.execute("PRAGMA trusted_schema = OFF")
        }
        let report = try MigrationRunner.migrate(database, migrations: migrations, now: now)
        if report.toVersion == Migrations.latestVersion { try verifySchema(database) }
        return LisaStorage(database: database, migration: report)
    }

    private init(database: SQLiteDatabase, migration: MigrationReport) {
        records = SQLiteRecordStore(database: database)
        rawContent = SQLiteRawContentStore(database: database)
        maintenance = SQLiteStoreMaintenance(database: database)
        self.migration = migration
        path = database.path
    }

    /// Confirms every collection and indexed column the code expects exists.
    private static func verifySchema(_ database: SQLiteDatabase) throws {
        try database.perform { session in
            for type in CollectionRegistry.all {
                let columns = Set(
                    try session.query("PRAGMA table_info(\(type.collectionName))").compactMap {
                        $0.count > 1 ? $0[1].text : nil
                    })
                let expected = Set(type.indexes.map(\.name) + ["id", "revision", "updated_at", "body"])
                let missing = expected.subtracting(columns)
                guard missing.isEmpty else {
                    throw StoreError.corrupt(
                        "collection \(type.collectionName) lacks columns \(missing.sorted().joined(separator: ", "))")
                }
            }
        }
    }
}
