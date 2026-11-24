// SQLite failures with their result codes and the engine's message.

/// A SQLite failure.
public struct SQLiteError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The primary result code (for example 19 for a constraint violation).
    public let code: Int32
    /// The extended result code.
    public let extendedCode: Int32
    public let message: String

    public init(code: Int32, extendedCode: Int32, message: String) {
        self.code = code
        self.extendedCode = extendedCode
        self.message = message
    }

    /// Whether the failure is a UNIQUE or PRIMARY KEY constraint violation.
    public var isUniqueViolation: Bool {
        code == 19 && (extendedCode == 2067 || extendedCode == 1555)
    }

    /// Whether the database was busy or locked.
    public var isBusy: Bool { code == 5 || code == 6 }

    /// Whether the statement was interrupted (`SQLITE_INTERRUPT`), as the reader monitor does (plan §8.15.2).
    public var isInterrupted: Bool { code == 9 }

    /// Whether the database or the disk is full (`SQLITE_FULL`, also `ENOSPC` while writing).
    public var isFull: Bool { code == 13 }

    public var description: String { "SQLite error \(extendedCode): \(message)" }
}
