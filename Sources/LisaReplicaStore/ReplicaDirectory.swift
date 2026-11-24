// The replica directory (plan §8.6.1, O-8): one per installation, owner-only, holding the database (with committed
// blobs inside it) and its WAL sidecars, incoming blob staging, the storage ballast (§8.15.2) and export staging. The
// Apple storage folder (`Apps/Shared/Storage`) also excludes it from device backups and protects it until first
// unlock; nothing here copies it anywhere.

import Foundation

/// The files and folders of one replica.
public struct ReplicaDirectory: Hashable, Sendable {
    public static let databaseName = "replica.sqlite"
    public static let blobStagingName = "blob-staging"
    public static let ballastName = "reserve.bin"
    public static let exportStagingName = "export-staging"

    public let path: String

    public var databasePath: String { path + "/" + Self.databaseName }
    public var blobStagingPath: String { path + "/" + Self.blobStagingName }
    public var ballastPath: String { path + "/" + Self.ballastName }
    public var exportStagingPath: String { path + "/" + Self.exportStagingName }

    /// Creates the directory and its folders where missing and makes all of them owner-only (0700). Files the store
    /// creates are owner-only too (0600).
    public static func prepare(at path: String) throws(ReplicaStoreError) -> ReplicaDirectory {
        let directory = ReplicaDirectory(path: path)
        for folder in [directory.path, directory.blobStagingPath, directory.exportStagingPath] {
            do {
                try FileManager.default.createDirectory(
                    atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
            } catch {
                throw .directory("\(folder): \(error.localizedDescription)")
            }
        }
        return directory
    }

    /// Brings the ballast to `bytes` of written zeros, so the space is really held. Returns whether it holds the full
    /// size: when storage is short the ballast is left empty and is restored later, when space returns (§8.15.2).
    @discardableResult
    public func restoreBallast(bytes: Int) throws(ReplicaStoreError) -> Bool {
        let manager = FileManager.default
        if !manager.fileExists(atPath: ballastPath) {
            guard manager.createFile(atPath: ballastPath, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw .directory("cannot create \(ballastPath)") }
        }
        let current = ((try? manager.attributesOfItem(atPath: ballastPath))?[.size] as? NSNumber)?.intValue ?? 0
        guard current < bytes else { return true }
        guard let handle = FileHandle(forWritingAtPath: ballastPath) else {
            throw .directory("cannot open \(ballastPath)")
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(current))
            var remaining = bytes - current
            let chunk = Data(count: min(remaining, 1 << 20))
            while remaining > 0 {
                let piece = remaining >= chunk.count ? chunk : chunk.prefix(remaining)
                try handle.write(contentsOf: piece)
                remaining -= piece.count
            }
            try handle.synchronize()
            return true
        } catch {
            try? handle.truncate(atOffset: 0)
            return false
        }
    }

    /// Empties the ballast so one capture can use its space (§8.15.2). Only the capture path calls this.
    public func releaseBallast() throws(ReplicaStoreError) {
        guard let handle = FileHandle(forWritingAtPath: ballastPath) else { return }
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: 0)
            try handle.synchronize()
        } catch {
            throw .io("cannot release \(ballastPath): \(error.localizedDescription)")
        }
    }

    /// The ballast's current size in bytes.
    public var ballastBytes: Int {
        ((try? FileManager.default.attributesOfItem(atPath: ballastPath))?[.size] as? NSNumber)?.intValue ?? 0
    }
}
