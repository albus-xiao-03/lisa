// The offline queue's file storage: one owner-only (0600) JSON document, replaced atomically on every save.

import Foundation

/// Keeps the offline queue in one JSON file that only the current user can read or write (mode 0600). Every save
/// replaces the file atomically and syncs it, so a crash leaves the previous queue or the new one.
public struct FileQueueStorage: QueueStorage {
    private static let format = "lisa-client-queue"
    private static let currentVersion = 1
    /// The largest queue file read, well above the queue's default body limit.
    private static let maxFileBytes = 64 * 1_048_576

    /// The queue file.
    public let fileURL: URL
    private let protection: Data.WritingOptions

    /// - Parameters:
    ///   - fileURL: the queue file. Its directory is created with mode 0700 when missing.
    ///   - protection: data-protection options for every write on Apple platforms, such as
    ///     `.completeFileProtectionUntilFirstUserAuthentication`, so actions taken on a locked device can be queued
    ///     (plan §6.5). Options other than data protection are ignored.
    public init(fileURL: URL, protection: Data.WritingOptions = []) {
        self.fileURL = fileURL
        self.protection = protection
    }

    public func load() throws -> [QueuedRequest] {
        OwnerOnlyFile.removeLeftoverStaging(in: fileURL.deletingLastPathComponent(), for: fileURL.lastPathComponent)
        guard let data = try file.read(exposure: .restrict) else { return [] }
        return try StorageCoding.decodeDocument(
            Document.self, from: data, format: Self.format, version: Self.currentVersion, path: fileURL.path
        ).entries
    }

    public func save(_ entries: [QueuedRequest]) throws {
        let document = Document(format: Self.format, version: Self.currentVersion, entries: entries)
        try file.write(try StorageCoding.encoder().encode(document))
    }

    private var file: OwnerOnlyFile {
        OwnerOnlyFile(url: fileURL, protection: protection, maxBytes: Self.maxFileBytes)
    }

    private struct Document: Codable {
        var format: String
        var version: Int
        var entries: [QueuedRequest]
    }
}
