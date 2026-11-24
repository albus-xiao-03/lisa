// The exclusive lock that makes one connection the only writer and checkpointer of a WAL database (docs/DECISIONS.md
// D-55): `flock` on `<database>.writer-lock`, held for the writer's lifetime. It excludes a second writer in another
// process and a second open in this one, since each open has its own open file description.

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Held while a `SQLiteWALDatabase` is open; released when it is deinitialized.
final class SQLiteWriterLock: @unchecked Sendable {
    let path: String
    private let descriptor: Int32

    /// Takes the lock without waiting, or throws `SQLITE_BUSY` if another writer holds it.
    init(path: String) throws {
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw SQLiteError(code: 14, extendedCode: 14, message: "cannot open the writer lock \(path)")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw SQLiteError(code: 5, extendedCode: 5, message: "another writer holds \(path)")
        }
        self.path = path
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
