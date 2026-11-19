// The TLS trust the owner supplies for a Lisa host: the host's certificate or its certificate authority, and
// optionally a SHA-256 pin of the host's own certificate.

import Foundation

/// What a device trusts for a Lisa host whose certificate the system does not trust, such as the certificate of
/// `lisa serve` with native TLS from the owner's own certificate authority (API-01, NOTIFY-07).
///
/// - `anchorCertificates`: the host's certificate, or the certificate authority that issued it, in DER form. The
///   device trusts only these for the host, never the system's roots, and certificate validation stays on.
/// - `leafCertificateSHA256`: when set, the host's own certificate must also have exactly this SHA-256 digest.
///
/// Certificates are public, so these settings are not secrets.
public struct HostTrustSettings: Codable, Hashable, Sendable {
    /// The length of a SHA-256 digest in bytes.
    public static let digestLength = 32
    /// The most certificates accepted.
    public static let maxCertificates = 8
    /// The largest certificate accepted, in DER bytes.
    public static let maxCertificateBytes = 65_536

    /// The DER certificates the host's certificate must chain to.
    public let anchorCertificates: [Data]
    /// The SHA-256 digest the host's own certificate must have, when pinned.
    public let leafCertificateSHA256: Data?

    /// Trust in `anchorCertificates` (DER), with an optional pin of the host's certificate.
    ///
    /// - Throws: `HostTrustSettingsError` for no certificate, too many or too large ones, or a pin that is not 32
    ///   bytes.
    public init(anchorCertificates: [Data], leafCertificateSHA256: Data? = nil) throws(HostTrustSettingsError) {
        try Self.validate(anchorCertificates, leafCertificateSHA256)
        self.anchorCertificates = anchorCertificates
        self.leafCertificateSHA256 = leafCertificateSHA256
    }

    /// Reads the certificate file the owner chose, PEM (one or more `BEGIN CERTIFICATE` blocks) or one DER
    /// certificate, and an optional pin of the host's certificate (`pinDigest(_:)`).
    public init(certificateFile: Data, leafPin: String? = nil) throws(HostTrustSettingsError) {
        let certificates: [Data]
        if let text = String(data: certificateFile, encoding: .utf8), text.contains(Self.pemBegin) {
            certificates = try Self.pemCertificates(text)
        } else if certificateFile.first == 0x30 {
            certificates = [certificateFile]
        } else {
            throw .noCertificate
        }
        var pin: Data?
        if let leafPin, !leafPin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pin = try Self.pinDigest(leafPin)
        }
        try self.init(anchorCertificates: certificates, leafCertificateSHA256: pin)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let anchors = try container.decode([Data].self, forKey: .anchorCertificates)
        let pin = try container.decodeIfPresent(Data.self, forKey: .leafCertificateSHA256)
        do throws(HostTrustSettingsError) {
            try Self.validate(anchors, pin)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .anchorCertificates, in: container, debugDescription: error.description)
        }
        anchorCertificates = anchors
        leafCertificateSHA256 = pin
    }

    /// Checks the certificates' count and sizes and the pin's length.
    private static func validate(_ anchors: [Data], _ pin: Data?) throws(HostTrustSettingsError) {
        guard !anchors.isEmpty, anchors.allSatisfy({ !$0.isEmpty }) else { throw .noCertificate }
        guard anchors.count <= maxCertificates else { throw .tooManyCertificates(limit: maxCertificates) }
        guard anchors.allSatisfy({ $0.count <= maxCertificateBytes }) else {
            throw .certificateTooLarge(limit: maxCertificateBytes)
        }
        if let pin, pin.count != digestLength { throw .invalidPin }
    }

    /// The 32 bytes of a SHA-256 pin: 64 hexadecimal digits, optionally separated by colons or spaces (as certificate
    /// tools print fingerprints), or the base64 form of the digest.
    public static func pinDigest(_ text: String) throws(HostTrustSettingsError) -> Data {
        let hex = text.filter { $0 != ":" && !$0.isWhitespace }
        if hex.count == digestLength * 2, hex.allSatisfy(\.isHexDigit) {
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else { throw .invalidPin }
                bytes.append(byte)
                index = next
            }
            return Data(bytes)
        }
        guard let decoded = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            decoded.count == digestLength
        else { throw .invalidPin }
        return decoded
    }

    private static let pemBegin = "-----BEGIN CERTIFICATE-----"
    private static let pemEnd = "-----END CERTIFICATE-----"

    /// The DER certificates of the `BEGIN CERTIFICATE` blocks in PEM text; other blocks, such as keys, are ignored.
    static func pemCertificates(_ text: String) throws(HostTrustSettingsError) -> [Data] {
        var certificates: [Data] = []
        var rest = Substring(text)
        while let begin = rest.range(of: pemBegin) {
            guard let end = rest[begin.upperBound...].range(of: pemEnd) else { throw .malformedPEM }
            let body = rest[begin.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
            guard let der = Data(base64Encoded: String(body)), !der.isEmpty else { throw .malformedPEM }
            certificates.append(der)
            guard certificates.count <= maxCertificates else { throw .tooManyCertificates(limit: maxCertificates) }
            rest = rest[end.upperBound...]
        }
        guard !certificates.isEmpty else { throw .noCertificate }
        return certificates
    }
}
