// A serialized SQLite connection: every use happens inside `perform`, under one lock, on one handle.

import CSQLite
import Foundation

/// `SQLITE_TRANSIENT`: SQLite copies bound text and blobs before the call returns.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One SQLite connection. All access is serialized; transactions are scoped to closures.
public final class SQLiteDatabase: @unchecked Sendable {
    private let handle: OpaquePointer
    private let lock = NSLock()
    /// Guards `owner`, the thread currently inside `perform`.
    private let ownerLock = NSLock()
    private var owner: ObjectIdentifier?
    public let path: String

    /// Opens (and with `create`, creates) the database at `path`.
    public init(path: String, readOnly: Bool = false, create: Bool = true) throws {
        var pointer: OpaquePointer?
        var flags = SQLITE_OPEN_FULLMUTEX
        flags |= readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
        if create && !readOnly { flags |= SQLITE_OPEN_CREATE }
        let result = sqlite3_open_v2(path, &pointer, flags, nil)
        guard result == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            if let pointer { sqlite3_close_v2(pointer) }
            throw SQLiteError(code: result, extendedCode: result, message: message)
        }
        handle = pointer
        self.path = path
        sqlite3_extended_result_codes(pointer, 1)
        sqlite3_busy_timeout(pointer, 5_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// The SQLite library version, such as `3.46.1`.
    public static var libraryVersion: String { String(cString: sqlite3_libversion()) }

    /// Runs `body` with exclusive use of the connection. Using the connection again from inside `body` on the same
    /// thread is a programming error: it fails immediately instead of deadlocking.
    @discardableResult
    public func perform<T>(_ body: (SQLiteSession) throws -> T) throws -> T {
        let current = ObjectIdentifier(Thread.current)
        let reentrant = ownerLock.withLock { owner == current }
        guard !reentrant else {
            throw SQLiteError(
                code: SQLITE_MISUSE, extendedCode: SQLITE_MISUSE,
                message: "the database was used again from inside one of its own transactions")
        }
        lock.lock()
        ownerLock.withLock { owner = current }
        defer {
            ownerLock.withLock { owner = nil }
            lock.unlock()
        }
        return try body(SQLiteSession(handle: handle))
    }

    /// Runs `body` in a write transaction (BEGIN IMMEDIATE); rolls back when it throws.
    @discardableResult
    public func writeTransaction<T>(_ body: (SQLiteSession) throws -> T) throws -> T {
        try perform { session in
            try session.execute("BEGIN IMMEDIATE")
            do {
                let result = try body(session)
                try session.execute("COMMIT")
                return result
            } catch {
                try? session.execute("ROLLBACK")
                throw error
            }
        }
    }

    /// Runs `body` in a read transaction, giving it a consistent snapshot.
    @discardableResult
    public func readTransaction<T>(_ body: (SQLiteSession) throws -> T) throws -> T {
        try perform { session in
            try session.execute("BEGIN DEFERRED")
            defer { try? session.execute("COMMIT") }
            return try body(session)
        }
    }

    /// Copies the whole database to `destination` with SQLite's online backup API.
    public func backup(to destination: String) throws {
        try perform { _ in
            let target = try SQLiteDatabase(path: destination)
            guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else {
                throw SQLiteError(
                    code: sqlite3_errcode(target.handle), extendedCode: sqlite3_extended_errcode(target.handle),
                    message: String(cString: sqlite3_errmsg(target.handle)))
            }
            let step = sqlite3_backup_step(backup, -1)
            let finish = sqlite3_backup_finish(backup)
            guard step == SQLITE_DONE, finish == SQLITE_OK else {
                throw SQLiteError(code: step, extendedCode: finish, message: "the backup did not complete")
            }
        }
    }
}

/// Statement execution for the duration of one `perform` call. Never escapes that call.
public struct SQLiteSession {
    let handle: OpaquePointer

    /// Executes one or more statements without parameters.
    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "statement failed"
            sqlite3_free(error)
            throw SQLiteError(code: result & 0xFF, extendedCode: sqlite3_extended_errcode(handle), message: message)
        }
    }

    /// Runs a statement with positional parameters and returns every row.
    @discardableResult
    public func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 =
                switch value {
                case .null: sqlite3_bind_null(statement, index)
                case .integer(let number): sqlite3_bind_int64(statement, index, number)
                case .real(let number): sqlite3_bind_double(statement, index, number)
                case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
                case .blob(let data):
                    data.withUnsafeBytes { raw in
                        sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), transient)
                    }
                }
            guard result == SQLITE_OK else { throw lastError() }
        }
        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw lastError() }
            let count = sqlite3_column_count(statement)
            rows.append(
                (0..<count).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
                    case SQLITE_BLOB:
                        let bytes = sqlite3_column_blob(statement, column)
                        let length = Int(sqlite3_column_bytes(statement, column))
                        return .blob(bytes.map { Data(bytes: $0, count: length) } ?? Data())
                    default: return .null
                    }
                })
        }
        return rows
    }

    /// Rows changed by the most recent statement.
    public var changes: Int { Int(sqlite3_changes(handle)) }

    /// Reads `PRAGMA user_version`.
    public func userVersion() throws -> Int {
        Int(try query("PRAGMA user_version").first?.first?.integer ?? 0)
    }

    /// Sets `PRAGMA user_version` (inside the current transaction).
    public func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func lastError() -> SQLiteError {
        SQLiteError(
            code: sqlite3_errcode(handle) & 0xFF, extendedCode: sqlite3_extended_errcode(handle),
            message: String(cString: sqlite3_errmsg(handle)))
    }
}
