// Applies migrations transactionally after a pre-migration backup; refuses newer schemas; never recreates data.

import Foundation
import LisaPorts
import LisaSQLite

/// What a migration run did.
public struct MigrationReport: Hashable, Sendable {
    public var fromVersion: Int
    public var toVersion: Int
    /// The copy taken before migrating an existing database, kept for recovery.
    public var preMigrationBackup: String?
}

/// Runs migrations.
enum MigrationRunner {
    static func migrate(_ database: SQLiteDatabase, migrations: [Migration], now: Date) throws -> MigrationReport {
        let current = try database.perform { try $0.userVersion() }
        let ordered = migrations.sorted { $0.version < $1.version }
        let latest = ordered.last?.version ?? 0
        if current > latest { throw StoreError.schemaTooNew(found: current, supported: latest) }
        guard current < latest else {
            return MigrationReport(fromVersion: current, toVersion: current, preMigrationBackup: nil)
        }
        var backupPath: String?
        if current > 0 {
            let stamp = Int64((now.timeIntervalSince1970 * 1000).rounded())
            let path = "\(database.path).pre-migration-v\(current)-\(stamp).sqlite"
            try database.backup(to: path)
            backupPath = path
        }
        var reached = current
        for migration in ordered where migration.version > current {
            do {
                try database.writeTransaction { session in
                    for statement in migration.statements { try session.execute(statement) }
                    try session.setUserVersion(migration.version)
                }
                reached = migration.version
            } catch {
                throw StoreError.migrationFailed(version: migration.version, reason: String(describing: error))
            }
        }
        return MigrationReport(fromVersion: current, toVersion: reached, preMigrationBackup: backupPath)
    }
}
