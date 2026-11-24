// What a long reader is for, and how long it may keep its snapshot (plan §8.15.2).

/// The purpose and time budget of a long read.
public struct SQLiteReaderPurpose: Hashable, Sendable, CustomStringConvertible {
    public let name: String
    public let budget: Duration

    public init(name: String, budget: Duration) {
        self.name = name
        self.budget = budget
    }

    /// A search query: 5 s.
    public static let search = SQLiteReaderPurpose(name: "search", budget: .seconds(5))
    /// One staging catch-up pass: 2 s.
    public static let catchUpPass = SQLiteReaderPurpose(name: "catch-up pass", budget: .seconds(2))
    /// Export assembly: 60 s.
    public static let export = SQLiteReaderPurpose(name: "export", budget: .seconds(60))
    /// Snapshot generation on Core: 10 minutes.
    public static let snapshotGeneration = SQLiteReaderPurpose(name: "snapshot generation", budget: .seconds(600))

    public var description: String { name }
}
