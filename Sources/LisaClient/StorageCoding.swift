// JSON coding of the client's own files: sorted keys, exactly round-tripping dates, and a versioned envelope header.

import Foundation

/// Encoders and decoders for the credential, queue and cache files.
///
/// Dates use `Date`'s own encoding (seconds since the reference date, as a JSON number), so stored values round-trip
/// exactly. Request and response bodies are stored as the API-encoded bytes the host receives or sent.
enum StorageCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// The `format` and `version` fields every client file starts with.
    struct Header: Decodable {
        var format: String
        var version: Int
    }

    /// Decodes a versioned client file: checks its format name and version first, then decodes the whole document.
    static func decodeDocument<Document: Decodable>(
        _ type: Document.Type, from data: Data, format: String, version: Int, path: String
    ) throws -> Document {
        let decoder = decoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw ClientStorageError.corrupted(path: path, reason: "not a \(format) file")
        }
        guard header.version == version else {
            throw ClientStorageError.unsupportedVersion(path: path, version: header.version)
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ClientStorageError.corrupted(path: path, reason: "the \(format) document is malformed")
        }
    }
}
