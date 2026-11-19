// The single-owner data-directory lock (ARCH-03): exactly one runtime may own a data directory at a time.

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Who holds a data directory.
public struct LockOwner: Codable, Hashable, Sendable, CustomStringConvertible {
    public var processID: Int32
    public var acquiredAt: Date
    public var mode: String

    public var description: String { "process \(processID) (\(mode)) since \(acquiredAt)" }
}

/// Why the runtime could not start or continue.
public enum RuntimeError: Error, Hashable, Sendable, CustomStringConvertible {
    /// Another runtime owns the data directory; connect to it as a client instead of starting a second writer.
    case dataDirectoryInUse(directory: String, owner: LockOwner?)
    case dataDirectoryUnusable(directory: String, reason: String)

    public var description: String {
        switch self {
        case .dataDirectoryInUse(let directory, let owner):
            "the data directory \(directory) is owned by another Lisa runtime"
                + (owner.map { " (\($0))" } ?? "") + "; stop it, or use it as a client"
        case .dataDirectoryUnusable(let directory, let reason):
            "the data directory \(directory) cannot be used: \(reason)"
        }
    }
}

/// An exclusive advisory lock on `<data directory>/lisa.lock`, held for the runtime's lifetime. The operating system
/// releases it if the process ends, so a crashed runtime never leaves a stale lock behind.
public final class DataDirectoryLock: @unchecked Sendable {
    public let directory: URL
    private let descriptor: Int32
    private let lock = NSLock()
    private var released = false

    private init(directory: URL, descriptor: Int32) {
        self.directory = directory
        self.descriptor = descriptor
    }

    /// Creates the directory with owner-only permissions if needed and takes the lock, or throws
    /// `RuntimeError.dataDirectoryInUse` without waiting.
    public static func acquire(directory: URL, mode: String, now: Date) throws -> DataDirectoryLock {
        let path = directory.path
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw RuntimeError.dataDirectoryUnusable(directory: path, reason: "it could not be created")
        }
        let lockPath = directory.appendingPathComponent("lisa.lock").path
        let descriptor = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else {
            throw RuntimeError.dataDirectoryUnusable(directory: path, reason: "the lock file could not be opened")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let owner = (try? Data(contentsOf: URL(fileURLWithPath: lockPath))).flatMap {
                try? JSONDecoder().decode(LockOwner.self, from: $0)
            }
            close(descriptor)
            throw RuntimeError.dataDirectoryInUse(directory: path, owner: owner)
        }
        let owner = LockOwner(processID: getpid(), acquiredAt: now, mode: mode)
        if let data = try? JSONEncoder().encode(owner) {
            _ = ftruncate(descriptor, 0)
            _ = data.withUnsafeBytes { pwrite(descriptor, $0.baseAddress, $0.count, 0) }
        }
        return DataDirectoryLock(directory: directory, descriptor: descriptor)
    }

    /// Releases the lock. Safe to call more than once.
    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard !released else { return }
        released = true
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    deinit {
        release()
    }
}
