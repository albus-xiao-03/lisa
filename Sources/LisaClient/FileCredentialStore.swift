// The command-line client's credential store: one owner-only (0600) JSON file, replaced atomically.

import Foundation

/// Keeps the client identity, including its device credential, in a JSON file that only the current user can read or
/// write (mode 0600), for the command-line client. Apple apps keep it in Keychain instead.
///
/// Loading refuses a file that other users can access, because its credential may have been exposed: restrict the
/// file with `chmod 600`, or remove it and pair again.
public struct FileCredentialStore: CredentialStore {
    private static let format = "lisa-client-identity"
    private static let currentVersion = 1
    private static let maxFileBytes = 65_536

    /// The identity file.
    public let fileURL: URL

    /// - Parameter fileURL: the identity file. Its directory is created with mode 0700 when missing.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ClientIdentity? {
        OwnerOnlyFile.removeLeftoverStaging(in: fileURL.deletingLastPathComponent(), for: fileURL.lastPathComponent)
        guard let data = try file.read(exposure: .refuse) else { return nil }
        return try StorageCoding.decodeDocument(
            Document.self, from: data, format: Self.format, version: Self.currentVersion, path: fileURL.path
        ).identity
    }

    public func save(_ identity: ClientIdentity) throws {
        let document = Document(format: Self.format, version: Self.currentVersion, identity: identity)
        try file.write(try StorageCoding.encoder().encode(document))
    }

    public func clear() throws {
        try file.remove()
    }

    private var file: OwnerOnlyFile {
        OwnerOnlyFile(url: fileURL, maxBytes: Self.maxFileBytes)
    }

    private struct Document: Codable {
        var format: String
        var version: Int
        var identity: ClientIdentity
    }
}
