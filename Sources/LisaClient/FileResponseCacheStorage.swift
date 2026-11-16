// The response cache's file storage: one owner-only (0600) JSON file per cache key, in a directory of its own.

import Foundation

/// Keeps cached responses as JSON files that only the current user can read or write (mode 0600), one per key, in a
/// directory used only by this cache.
public struct FileResponseCacheStorage: ResponseCacheStorage {
    private static let fileExtension = "json"
    /// The largest cached file read.
    private static let maxFileBytes = 16 * 1_048_576

    /// The cache directory. It is created with mode 0700 when missing.
    public let directory: URL
    private let protection: Data.WritingOptions

    /// - Parameters:
    ///   - directory: a directory used only by this cache.
    ///   - protection: data-protection options for every write on Apple platforms, such as
    ///     `.completeFileProtectionUntilFirstUserAuthentication`. Options other than data protection are ignored.
    public init(directory: URL, protection: Data.WritingOptions = []) {
        self.directory = directory
        self.protection = protection
    }

    public func read(_ key: CacheKey) throws -> Data? {
        try file(for: key).read(exposure: .restrict)
    }

    public func write(_ data: Data, for key: CacheKey) throws {
        try file(for: key).write(data)
    }

    public func remove(_ key: CacheKey) throws {
        try file(for: key).remove()
    }

    public func keys() throws -> [CacheKey] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        } catch {
            throw ClientStorageError.ioFailure(path: directory.path, reason: error.localizedDescription)
        }
        OwnerOnlyFile.removeLeftoverStaging(in: directory)
        let suffix = ".\(Self.fileExtension)"
        return names.compactMap { name in
            name.hasSuffix(suffix) ? CacheKey(name: String(name.dropLast(suffix.count))) : nil
        }
        .sorted { $0.name < $1.name }
    }

    public func removeAll() throws {
        for key in try keys() {
            try remove(key)
        }
    }

    private func file(for key: CacheKey) -> OwnerOnlyFile {
        OwnerOnlyFile(
            url: directory.appendingPathComponent("\(key.name).\(Self.fileExtension)"), protection: protection,
            maxBytes: Self.maxFileBytes)
    }
}
