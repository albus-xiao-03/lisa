// The shared decoding rule for owner texts, `lisa-pair:4:` and `lisa-reanchor:2:` (plan §8.1.2 step 2).

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Encodes and decodes owner texts: `<kind>:<version>:` followed by unpadded base64url of a canonical JSON object
/// carrying `version` and a four-byte `checksum`. The checksum is the first four bytes of SHA-256 over the ASCII
/// prefix (through its final colon) followed by the canonical object without `checksum`.
public enum OwnerTextCodec {
    /// The longest owner text accepted, checked before any decoding.
    public static let maximumLength = 4096

    /// The text for `fields` (which must not contain `version` or `checksum`) under `prefix`.
    public static func encode(prefix: String, version: Int64, fields: [(String, CanonicalValue)]) throws(TrustError)
        -> String
    {
        let withVersion = fields + [("version", .integer(version))]
        let unchecked = try object(withVersion)
        let checksum = try checksumBytes(prefix: prefix, uncheckedObject: unchecked)
        let full = try object(withVersion + [("checksum", .string(StrictBase64URL.encode(checksum)))])
        let canonical = try canonicalBytes(.object(full))
        let text = prefix + StrictBase64URL.encode(canonical)
        guard text.utf8.count <= maximumLength else { throw .ownerTextTooLong(text.utf8.count) }
        return text
    }

    /// The verified object, without `checksum` and `version`, of a text under `prefix`.
    /// - Parameter outdatedPrefixes: earlier formats, refused with `outdatedOwnerText` before anything is decoded.
    public static func decode(_ text: String, prefix: String, version: Int64, outdatedPrefixes: [String])
        throws(TrustError) -> CanonicalFieldReader
    {
        let bytes = Array(text.utf8)
        guard bytes.count <= maximumLength else { throw .ownerTextTooLong(bytes.count) }
        guard bytes.allSatisfy({ $0 < 0x80 }) else { throw .ownerTextNotASCII }
        if let old = outdatedPrefixes.first(where: { text.hasPrefix($0) }) { throw .outdatedOwnerText(prefix: old) }
        guard text.hasPrefix(prefix) else { throw .unknownOwnerText }
        let payload = String(text.dropFirst(prefix.count))
        guard let json = try? StrictBase64URL.decode(payload) else { throw .payloadEncoding }
        let value: CanonicalValue
        do {
            value = try CanonicalDecoder.decode(json, limits: CanonicalLimits(maxBytes: maximumLength))
        } catch {
            throw .payloadNotCanonical(error)
        }
        guard case .object(let full) = value else { throw .field(.notAnObject) }
        var reader = CanonicalFieldReader(object: full)
        let found: Int64
        let checksumText: String
        do {
            found = try reader.integer("version")
            checksumText = try reader.string("checksum")
        } catch {
            throw .field(error)
        }
        guard found == version else { throw .versionMismatch(expected: version, found: found) }
        guard let checksum = try? StrictBase64URL.decode(checksumText), checksum.count == 4 else {
            throw .invalidField("checksum")
        }
        let unchecked = try object(full.members.filter { $0.key != "checksum" }.map { ($0.key, $0.value) })
        guard try checksumBytes(prefix: prefix, uncheckedObject: unchecked) == checksum else { throw .checksumMismatch }
        return reader
    }

    static func checksumBytes(prefix: String, uncheckedObject: CanonicalObject) throws(TrustError) -> [UInt8] {
        let input = Array(prefix.utf8) + (try canonicalBytes(.object(uncheckedObject)))
        return Array([UInt8](Digests.sha256(Data(input))).prefix(4))
    }

    static func object(_ pairs: [(String, CanonicalValue)]) throws(TrustError) -> CanonicalObject {
        do {
            return try CanonicalObject(pairs)
        } catch {
            throw .payloadNotCanonical(error)
        }
    }

    static func canonicalBytes(_ value: CanonicalValue) throws(TrustError) -> [UInt8] {
        do {
            return try CanonicalEncoder.encode(value, limits: CanonicalLimits(maxBytes: maximumLength))
        } catch {
            throw .payloadNotCanonical(error)
        }
    }
}
