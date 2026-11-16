// Owner-only client files: atomic, synced replacement through a private staging directory, and guarded reads.

import Foundation

/// A file that only the current user can read or write (mode 0600), replaced atomically on every write.
///
/// A write creates the new content inside a fresh staging directory with mode 0700 next to the file, so the bytes are
/// never reachable by other users whatever the process umask is. The content is synced to storage, then moved over the
/// file in one step. The destination entry itself is replaced, never written through, so a symbolic link placed there
/// cannot redirect the write. Reads refuse anything that is not a regular file.
struct OwnerOnlyFile: Sendable {
    /// What a read does with a file that other users can access.
    enum Exposure: Sendable {
        /// Refuse to read it, for secrets that may already have been exposed.
        case refuse
        /// Restrict it to the owner, then read it.
        case restrict
    }

    static let fileMode = 0o600
    static let directoryMode = 0o700
    private static let stagingSuffix = ".staging"

    let url: URL
    /// Data-protection options applied when the file is created on Apple platforms.
    let protection: Data.WritingOptions
    /// The largest file a read accepts.
    let maxBytes: Int

    /// - Parameter protection: only the data-protection options are kept; atomicity is this type's own.
    init(url: URL, protection: Data.WritingOptions = [], maxBytes: Int) {
        self.url = url
        self.protection = protection.intersection(.fileProtectionMask)
        self.maxBytes = maxBytes
    }

    /// The file's contents, or `nil` when it does not exist.
    func read(exposure: Exposure) throws -> Data? {
        let manager = FileManager.default
        let path = url.path
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: path)
        } catch {
            if Self.isMissing(error) { return nil }
            throw ClientStorageError.ioFailure(path: path, reason: Self.reason(error))
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw ClientStorageError.notARegularFile(path: path)
        }
        if let size = (attributes[.size] as? NSNumber)?.intValue, size > maxBytes {
            throw ClientStorageError.tooLarge(path: path, limit: maxBytes)
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        if permissions & 0o077 != 0 {
            switch exposure {
            case .refuse:
                throw ClientStorageError.unprotectedFile(path: path)
            case .restrict:
                do {
                    try manager.setAttributes([.posixPermissions: Self.fileMode], ofItemAtPath: path)
                } catch {
                    throw ClientStorageError.ioFailure(path: path, reason: Self.reason(error))
                }
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isMissing(error) { return nil }
            throw ClientStorageError.ioFailure(path: path, reason: Self.reason(error))
        }
        guard data.count <= maxBytes else { throw ClientStorageError.tooLarge(path: path, limit: maxBytes) }
        return data
    }

    /// Replaces the file's contents atomically, with owner-only permissions.
    func write(_ data: Data) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try Self.prepareDirectory(directory)
        let staging = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString.lowercased())\(Self.stagingSuffix)", isDirectory: true)
        do {
            try manager.createDirectory(
                at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: Self.directoryMode])
        } catch {
            throw ClientStorageError.ioFailure(path: staging.path, reason: Self.reason(error))
        }
        defer { try? manager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(url.lastPathComponent)
        do {
            try data.write(to: staged, options: protection.union(.withoutOverwriting))
            try manager.setAttributes([.posixPermissions: Self.fileMode], ofItemAtPath: staged.path)
            try Self.synchronize(staged)
            try replace(with: staged)
        } catch let error as ClientStorageError {
            throw error
        } catch {
            throw ClientStorageError.ioFailure(path: url.path, reason: Self.reason(error))
        }
        Self.synchronizeDirectory(directory)
    }

    /// Removes the file; a missing file is not an error.
    func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            if Self.isMissing(error) { return }
            throw ClientStorageError.ioFailure(path: url.path, reason: Self.reason(error))
        }
    }

    /// Creates `directory`, and any missing parent, with mode 0700 when it does not exist.
    static func prepareDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ClientStorageError.notADirectory(path: directory.path) }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: directoryMode])
        } catch {
            throw ClientStorageError.ioFailure(path: directory.path, reason: reason(error))
        }
    }

    /// Removes staging directories that interrupted writes left in `directory`: those of `fileName`, or of any file
    /// when `fileName` is `nil` (for a directory the caller owns entirely).
    static func removeLeftoverStaging(in directory: URL, for fileName: String? = nil) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let prefix = fileName.map { ".\($0)." } ?? "."
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(stagingSuffix) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// Moves `staged` over the destination in one step.
    private func replace(with staged: URL) throws {
        let manager = FileManager.default
        if let existing = try? manager.attributesOfItem(atPath: url.path) {
            guard existing[.type] as? FileAttributeType != .typeDirectory else {
                throw ClientStorageError.notARegularFile(path: url.path)
            }
            _ = try manager.replaceItemAt(url, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly)
            return
        }
        do {
            try manager.moveItem(at: staged, to: url)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            _ = try manager.replaceItemAt(url, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly)
        }
    }

    /// Flushes a file's contents to storage before it replaces the destination.
    private static func synchronize(_ file: URL) throws {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    /// Flushes the directory entry of the replacement where the platform allows it; the replacement itself is
    /// already atomic.
    private static func synchronizeDirectory(_ directory: URL) {
        guard let handle = try? FileHandle(forReadingFrom: directory) else { return }
        try? handle.synchronize()
        try? handle.close()
    }

    private static func isMissing(_ error: any Error) -> Bool {
        guard let error = error as? CocoaError else { return false }
        return error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    }

    private static func reason(_ error: any Error) -> String {
        (error as? CocoaError)?.localizedDescription ?? String(describing: error)
    }
}
