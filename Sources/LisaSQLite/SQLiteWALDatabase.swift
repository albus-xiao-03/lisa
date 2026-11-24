// A WAL-mode database with exactly one read-write connection (docs/DECISIONS.md D-55): SQLite's WAL-reset bug needs two
// connections writing or checkpointing at the same instant, and the loaded library isn't shown to carry its fix. The
// writer holds `<database>.writer-lock` for its lifetime and performs every write and every checkpoint; every other
// connection is read-only and never writes or checkpoints, not even when it closes.

import Foundation

/// The single writer of a WAL database, and the factory of its read-only connections.
public final class SQLiteWALDatabase: @unchecked Sendable {
    public let path: String
    /// The only read-write connection.
    public let writer: SQLiteDatabase
    private let lock: SQLiteWriterLock

    /// Takes the writer lock (throwing `SQLITE_BUSY` if another writer holds it), opens the read-write connection and
    /// puts the database in WAL mode.
    public init(path: String) throws {
        lock = try SQLiteWriterLock(path: path + ".writer-lock")
        writer = try SQLiteDatabase(path: path)
        self.path = path
        let mode = try writer.perform { session in try session.query("PRAGMA journal_mode = WAL") }
        guard mode.first?.first?.text?.lowercased() == "wal" else {
            throw SQLiteError(code: 1, extendedCode: 1, message: "\(path) could not enter WAL mode")
        }
    }

    /// A new read-only connection: it reads committed data and never writes or checkpoints.
    public func openReader() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: path, readOnly: true, create: false)
    }

    /// A checkpoint on the writer, the only connection allowed to run one.
    @discardableResult
    public func checkpoint(_ mode: SQLiteCheckpointMode) throws -> SQLiteCheckpointResult {
        let row =
            try writer.perform { session in try session.query("PRAGMA wal_checkpoint(\(mode.rawValue))") }.first ?? []
        guard row.count == 3, let busy = row[0].integer, let log = row[1].integer, let done = row[2].integer else {
            throw SQLiteError(code: 1, extendedCode: 1, message: "unexpected wal_checkpoint result")
        }
        return SQLiteCheckpointResult(busy: busy != 0, logFrames: Int(log), checkpointedFrames: Int(done))
    }
}
