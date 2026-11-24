// What `PRAGMA wal_checkpoint` reports: whether it was blocked, the WAL's frames and how many were checkpointed.

/// A checkpoint's outcome.
public struct SQLiteCheckpointResult: Hashable, Sendable {
    /// The checkpoint couldn't complete because of readers or another writer (`SQLITE_BUSY`).
    public let busy: Bool
    /// Frames in the WAL, or -1 if the database isn't in WAL mode.
    public let logFrames: Int
    /// Frames checkpointed into the database, or -1.
    public let checkpointedFrames: Int

    public init(busy: Bool, logFrames: Int, checkpointedFrames: Int) {
        self.busy = busy
        self.logFrames = logFrames
        self.checkpointedFrames = checkpointedFrames
    }
}
