// Restores a backup after checking its manifest, integrity and schema; the replaced database is kept, never deleted.

import Foundation
import LisaDomain
import LisaPorts
import LisaSQLite

/// What a restore did.
public struct RestoreReport: Hashable, Sendable {
    public var restoredSchemaVersion: Int
    /// Where the database that was replaced now lives.
    public var previousDatabaseMovedTo: String?
}

/// Backup restoration. The caller must hold the data-directory lock so that no runtime has the database open.
public enum StoreRestore {
    public static func restore(backupFile: URL, databasePath: String, now: Date) throws -> RestoreReport {
        let manifestURL = backupFile.appendingPathExtension("manifest.json")
        guard let manifestData = FileManager.default.contents(atPath: manifestURL.path) else {
            throw StoreError.corrupt("the backup has no manifest at \(manifestURL.lastPathComponent)")
        }
        let manifest: BackupManifest
        do {
            manifest = try DomainJSON.decoder().decode(BackupManifest.self, from: manifestData)
        } catch {
            throw StoreError.corrupt("the backup manifest cannot be read")
        }
        guard manifest.format == SQLiteStoreMaintenance.backupFormat else {
            throw StoreError.corrupt("unknown backup format \(manifest.format)")
        }
        guard manifest.schemaVersion <= Migrations.latestVersion else {
            throw StoreError.schemaTooNew(found: manifest.schemaVersion, supported: Migrations.latestVersion)
        }
        do {
            let backup = try SQLiteDatabase(path: backupFile.path, readOnly: true, create: false)
            let (integrity, version) = try backup.perform { session in
                (try session.query("PRAGMA integrity_check").first?.first?.text, try session.userVersion())
            }
            guard integrity == "ok" else { throw StoreError.corrupt("the backup failed its integrity check") }
            guard version == manifest.schemaVersion else {
                throw StoreError.corrupt(
                    "the backup schema \(version) does not match its manifest (\(manifest.schemaVersion))")
            }
        }
        let manager = FileManager.default
        var movedTo: String?
        if manager.fileExists(atPath: databasePath) {
            let stamp = Int64((now.timeIntervalSince1970 * 1000).rounded())
            let target = "\(databasePath).before-restore-\(stamp)"
            try manager.moveItem(atPath: databasePath, toPath: target)
            for suffix in ["-wal", "-shm"] where manager.fileExists(atPath: databasePath + suffix) {
                try manager.moveItem(atPath: databasePath + suffix, toPath: target + suffix)
            }
            movedTo = target
        }
        try manager.copyItem(atPath: backupFile.path, toPath: databasePath)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databasePath)
        return RestoreReport(restoredSchemaVersion: manifest.schemaVersion, previousDatabaseMovedTo: movedTo)
    }
}
