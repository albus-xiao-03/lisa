// One long reader the monitor released (plan §8.15.2): its purpose, why, how long its snapshot had been open, and
// the truncating checkpoint that followed.

/// A released reader.
public struct SQLiteReaderRelease: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// Open longer than its purpose's budget.
        case overBudget
        /// Free space fell below the reserve plus twice the WAL size.
        case lowSpace(availableBytes: Int64, walBytes: Int64)
    }

    public let purpose: SQLiteReaderPurpose
    public let reason: Reason
    public let openFor: Duration
    /// The checkpoint run on the writer after the release; `nil` if it couldn't run.
    public let checkpoint: SQLiteCheckpointResult?

    public init(
        purpose: SQLiteReaderPurpose, reason: Reason, openFor: Duration, checkpoint: SQLiteCheckpointResult?
    ) {
        self.purpose = purpose
        self.reason = reason
        self.openFor = openFor
        self.checkpoint = checkpoint
    }
}
