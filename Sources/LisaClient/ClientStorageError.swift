// Errors of the client's own files: exposure to other users, wrong file types, size limits, formats and I/O.

import Foundation

/// Why a client file (credential, queue or cache) could not be read or written. Descriptions name the path only.
public enum ClientStorageError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The file is readable or writable by other users, so a secret in it may have been exposed.
    case unprotectedFile(path: String)
    /// The path is not a regular file, for example a symbolic link or a directory.
    case notARegularFile(path: String)
    /// The path exists and is not a directory.
    case notADirectory(path: String)
    /// The file is larger than its limit.
    case tooLarge(path: String, limit: Int)
    /// The file is not in the expected format.
    case corrupted(path: String, reason: String)
    /// The file was written in a format version this client does not read.
    case unsupportedVersion(path: String, version: Int)
    /// The file system refused an operation.
    case ioFailure(path: String, reason: String)

    public var description: String {
        switch self {
        case .unprotectedFile(let path):
            "\(path) is accessible to other users; restrict it with chmod 600, or remove it and pair again"
        case .notARegularFile(let path): "\(path) is not a regular file"
        case .notADirectory(let path): "\(path) is not a directory"
        case .tooLarge(let path, let limit): "\(path) is larger than \(limit) bytes"
        case .corrupted(let path, let reason): "\(path) is unreadable: \(reason)"
        case .unsupportedVersion(let path, let version):
            "\(path) uses format version \(version), which is not supported"
        case .ioFailure(let path, let reason): "\(path): \(reason)"
        }
    }
}
