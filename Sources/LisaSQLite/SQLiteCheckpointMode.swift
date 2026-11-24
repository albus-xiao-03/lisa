// The checkpoint modes of `PRAGMA wal_checkpoint` (sqlite.org `pragma.html#pragma_wal_checkpoint`).

/// How a checkpoint treats readers and the WAL file.
public enum SQLiteCheckpointMode: String, Sendable, CaseIterable {
    /// Copies what it can without waiting for readers.
    case passive = "PASSIVE"
    /// Waits for writers, then copies every frame readers allow.
    case full = "FULL"
    /// As `full`, then waits until readers are done with the WAL, so the next writer restarts it.
    case restart = "RESTART"
    /// As `restart`, then truncates the WAL file to zero bytes.
    case truncate = "TRUNCATE"
}
