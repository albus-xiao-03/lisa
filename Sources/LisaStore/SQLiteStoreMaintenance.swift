// Integrity checks and consistent, versioned backups using SQLite's online backup API.

import Foundation
import LisaDomain
import LisaPorts
import LisaSQLite

/// The SQLite implementation of StoreMaintenance.
public final class SQLiteStoreMaintenance: StoreMaintenance {
    /// The backup format identifier written into every manifest.
    public static let backupFormat = "lisa-sqlite-backup-1"
    let database: SQLiteDatabase

    init(database: SQLiteDatabase) {
        self.database = database
    }

    public var schemaVersion: Int {
        get throws { try database.perform { try $0.userVersion() } }
    }

    public func checkIntegrity() throws {
        let result = try database.perform { try $0.query("PRAGMA integrity_check").first?.first?.text }
        guard result == "ok" else { throw StoreError.corrupt(result ?? "no result") }
    }

    public func backup(to directory: URL, now: Date, applicationVersion: String) throws -> BackupManifest {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int64((now.timeIntervalSince1970 * 1000).rounded())
        let file = directory.appendingPathComponent("lisa-backup-\(stamp).sqlite")
        try database.backup(to: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var counts: [String: Int] = [:]
        let version = try schemaVersion
        try database.perform { session in
            for name in CollectionRegistry.collectionNames.sorted() {
                counts[name] = Int(try session.query("SELECT COUNT(*) FROM \(name)").first?.first?.integer ?? 0)
            }
        }
        let manifest = BackupManifest(
            format: SQLiteStoreMaintenance.backupFormat, schemaVersion: version, createdAt: now,
            applicationVersion: applicationVersion, recordCounts: counts)
        let manifestFile = file.appendingPathExtension("manifest.json")
        let encoder = DomainJSON.encoder()
        encoder.outputFormatting.insert(.prettyPrinted)
        try encoder.encode(manifest).write(to: manifestFile, options: .atomic)
        return manifest
    }
}
