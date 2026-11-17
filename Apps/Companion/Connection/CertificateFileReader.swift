// Reads the certificate file the owner chose in the system's file picker, within a size bound, with the
// security-scoped access the picker grants.

import Foundation

/// Reads a chosen certificate file. `HostTrustSettings` then checks that it holds PEM or DER certificates.
enum CertificateFileReader {
    /// The largest file read, comfortably above the certificates `HostTrustSettings` accepts.
    static let maxBytes = 1_048_576

    /// Why a chosen file was not read. The descriptions never repeat the file's content or its location.
    enum Failure: Error, CustomStringConvertible {
        /// The file is larger than a certificate file can be.
        case tooLarge
        /// The file could not be opened or read.
        case unreadable

        var description: String {
            switch self {
            case .tooLarge: "the file is larger than 1 MB, so it is not a certificate file"
            case .unreadable: "the file couldn't be opened"
            }
        }
    }

    /// The bytes of the file at `url`, read with the security-scoped access the file picker grants.
    static func read(_ url: URL) throws(Failure) -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            throw .tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw .unreadable }
        guard data.count <= maxBytes else { throw .tooLarge }
        return data
    }
}
