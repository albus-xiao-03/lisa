// How the CLI in client mode reaches a host already running on this machine (ARCH-03): `lisa serve` writes the owner
// listener's port and this run's owner credential to an owner-only (0600) file inside the data directory, and client
// mode reads it. The credential is a secret and is never described, reflected or logged.

import Foundation

/// The owner listener of one running host.
public struct OwnerEndpoint: Codable, Hashable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The owner listener's port on 127.0.0.1.
    public var port: Int
    /// The owner credential issued for this run. It is a secret.
    public var credential: String
    /// The serving process.
    public var processID: Int32
    public var issuedAt: Date

    public init(port: Int, credential: String, processID: Int32, issuedAt: Date) {
        self.port = port
        self.credential = credential
        self.processID = processID
        self.issuedAt = issuedAt
    }

    public var description: String {
        "OwnerEndpoint(port: \(port), process: \(processID), credential: <redacted>)"
    }

    public var debugDescription: String { description }

    /// Reflection, as used by `dump` and debuggers, shows the credential redacted.
    public var customMirror: Mirror {
        Mirror(
            self, children: ["port": port, "processID": processID, "issuedAt": issuedAt, "credential": "<redacted>"],
            displayStyle: .struct)
    }
}

/// The owner endpoint file `<data directory>/run/owner-endpoint.json`.
public struct OwnerEndpointFile: Sendable {
    private static let format = "lisa-owner-endpoint"
    private static let currentVersion = 1
    private static let maxFileBytes = 4_096

    public let fileURL: URL

    public init(dataDirectory: URL) {
        fileURL = dataDirectory.appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("owner-endpoint.json")
    }

    /// Replaces the file atomically; its directory is created with mode 0700 when missing.
    public func write(_ endpoint: OwnerEndpoint) throws {
        let document = Document(format: Self.format, version: Self.currentVersion, endpoint: endpoint)
        try file.write(try StorageCoding.encoder().encode(document))
    }

    /// The endpoint, or `nil` when no host has written one. A file that other users can access is refused, because
    /// its credential may have been exposed.
    public func read() throws -> OwnerEndpoint? {
        OwnerOnlyFile.removeLeftoverStaging(in: fileURL.deletingLastPathComponent(), for: fileURL.lastPathComponent)
        guard let data = try file.read(exposure: .refuse) else { return nil }
        return try StorageCoding.decodeDocument(
            Document.self, from: data, format: Self.format, version: Self.currentVersion, path: fileURL.path
        ).endpoint
    }

    /// Removes the file when the host stops serving.
    public func remove() throws {
        try file.remove()
    }

    private var file: OwnerOnlyFile {
        OwnerOnlyFile(url: fileURL, maxBytes: Self.maxFileBytes)
    }

    private struct Document: Codable {
        var format: String
        var version: Int
        var endpoint: OwnerEndpoint
    }
}
