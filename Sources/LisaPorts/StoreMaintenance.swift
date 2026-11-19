// Store maintenance: schema information, integrity checks and versioned backups (DATA-02, DATA-05).

import Foundation

/// The manifest written next to every backup, so a restore can check compatibility.
public struct BackupManifest: Hashable, Codable, Sendable {
    public var format: String
    public var schemaVersion: Int
    public var createdAt: Date
    public var applicationVersion: String
    public var recordCounts: [String: Int]

    public init(
        format: String, schemaVersion: Int, createdAt: Date, applicationVersion: String, recordCounts: [String: Int]
    ) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.applicationVersion = applicationVersion
        self.recordCounts = recordCounts
    }
}

/// Maintenance operations on the store.
public protocol StoreMaintenance: Sendable {
    var schemaVersion: Int { get throws }
    /// Runs SQLite's integrity check; throws `StoreError.corrupt` on failure.
    func checkIntegrity() throws
    /// Writes a consistent copy and its manifest to `directory`; returns the manifest.
    func backup(to directory: URL, now: Date, applicationVersion: String) throws -> BackupManifest
}
