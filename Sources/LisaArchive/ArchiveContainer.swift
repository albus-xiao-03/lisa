// The byte layout of a `lisa-archive` v1 file (plan §8.6.6).

/// `"LISA-ARCHIVE-V1\n"` (16 bytes) ‖ header length (4 bytes, big-endian) ‖ canonical header ‖ ciphertext length
/// (8 bytes, big-endian, equal to the header's `payloadLength`) ‖ AES-256-GCM ciphertext and tag ‖ one byte 0 or 1 ‖
/// the 64-byte signature when that byte is 1 (and only when the header names a signer).
public struct ArchiveContainer: Hashable, Sendable {
    public static let magic = Array("LISA-ARCHIVE-V1\n".utf8)
    public static let maximumHeaderBytes = 1_048_576

    public let headerBody: [UInt8]
    public let header: ArchiveHeader
    public let ciphertext: [UInt8]
    public let signature: [UInt8]?

    init(headerBody: [UInt8], header: ArchiveHeader, ciphertext: [UInt8], signature: [UInt8]?) {
        self.headerBody = headerBody
        self.header = header
        self.ciphertext = ciphertext
        self.signature = signature
    }

    /// The file bytes.
    public var bytes: [UInt8] {
        var out = Self.magic
        out += bigEndian(UInt64(headerBody.count), width: 4) + headerBody
        out += bigEndian(UInt64(ciphertext.count), width: 8) + ciphertext
        if let signature {
            out += [1] + signature
        } else {
            out += [0]
        }
        return out
    }

    /// Parses a file without decrypting or verifying anything.
    public static func parse(_ bytes: [UInt8]) throws(ArchiveError) -> ArchiveContainer {
        guard bytes.count >= magic.count + 4, Array(bytes.prefix(magic.count)) == magic else {
            throw .malformedContainer("magic")
        }
        var index = magic.count
        let headerLength = Int(readBigEndian(bytes, at: index, width: 4))
        index += 4
        guard headerLength <= maximumHeaderBytes, index + headerLength + 8 <= bytes.count else {
            throw .malformedContainer("header length")
        }
        let headerBody = Array(bytes[index..<(index + headerLength)])
        index += headerLength
        let header = try ArchiveHeader.decode(headerBody)
        let cipherLength = readBigEndian(bytes, at: index, width: 8)
        index += 8
        guard cipherLength == UInt64(header.payloadLength), UInt64(bytes.count - index) >= cipherLength + 1 else {
            throw .malformedContainer("ciphertext length")
        }
        let ciphertext = Array(bytes[index..<(index + Int(cipherLength))])
        index += Int(cipherLength)
        let flag = bytes[index]
        index += 1
        let signature: [UInt8]?
        switch flag {
        case 0:
            signature = nil
        case 1:
            guard bytes.count - index == 64 else { throw .malformedContainer("signature") }
            signature = Array(bytes[index...])
            index += 64
        default:
            throw .malformedContainer("signature flag")
        }
        guard index == bytes.count else { throw .malformedContainer("trailing bytes") }
        guard (signature == nil) == (header.signerKeyID == nil) else { throw .malformedContainer("signer") }
        return ArchiveContainer(headerBody: headerBody, header: header, ciphertext: ciphertext, signature: signature)
    }

    /// What the exporting device signs: the two digests after the archive domain.
    var signedDigests: [UInt8] { ArchiveDigest.sha256(headerBody) + ArchiveDigest.sha256(ciphertext) }

    func bigEndian(_ value: UInt64, width: Int) -> [UInt8] {
        (0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64(width - 1 - $0))) }
    }

    static func readBigEndian(_ bytes: [UInt8], at index: Int, width: Int) -> UInt64 {
        (0..<width).reduce(0) { $0 << 8 | UInt64(bytes[index + $1]) }
    }
}
