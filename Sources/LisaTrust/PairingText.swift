// The owner-issued pairing text `lisa-pair:4:` (plan §8.1.2 step 2), shared by the Core CLI and device parsers.

import Foundation
import LisaSyncProtocol

/// What `lisa core device enroll` shows once at the owner's terminal: Core's URL, trust mode, leaf SPKI pin, the
/// owner-CA digest in `ca` mode, dataset and enrollment IDs, the token, the expiry, and Core's complete signing public
/// key with its full fingerprint. `description` never shows the token.
public struct PairingText: Hashable, Sendable, CustomStringConvertible {
    public static let prefix = "lisa-pair:4:"
    public static let version: Int64 = 4
    /// Earlier formats, refused before a token could be sent: the owner issues current text instead.
    public static let outdatedPrefixes = ["lisa-pair:1:", "lisa-pair:2:", "lisa-pair:3:"]

    public enum TrustMode: String, Hashable, Sendable {
        case ca
        case pin
    }

    public let coreURL: String
    public let trustMode: TrustMode
    /// SHA-256 of the Core TLS leaf's SubjectPublicKeyInfo.
    public let leafPin: Digest256
    /// SHA-256 of the owner CA certificate's DER, in `ca` mode only.
    public let caDigest: Digest256?
    public let datasetID: Identifier128
    public let enrollmentID: Identifier128
    public let token: EnrollmentToken
    /// The enrollment's expiry, in Unix milliseconds.
    public let expiresAt: Int64
    public let coreSigningKey: CoreSigningIdentity

    /// - Throws: `TrustError.invalidCoreURL` or `.trustModeFields` when the fields break the format's rules.
    public init(
        coreURL: String, trustMode: TrustMode, leafPin: Digest256, caDigest: Digest256?, datasetID: Identifier128,
        enrollmentID: Identifier128, token: EnrollmentToken, expiresAt: Int64, coreSigningKey: CoreSigningIdentity
    ) throws(TrustError) {
        guard Self.isValidCoreURL(coreURL) else { throw .invalidCoreURL }
        guard (trustMode == .ca) == (caDigest != nil) else { throw .trustModeFields }
        self.coreURL = coreURL
        self.trustMode = trustMode
        self.leafPin = leafPin
        self.caDigest = caDigest
        self.datasetID = datasetID
        self.enrollmentID = enrollmentID
        self.token = token
        self.expiresAt = expiresAt
        self.coreSigningKey = coreSigningKey
    }

    /// The owner text.
    public func encoded() throws(TrustError) -> String {
        var fields: [(String, CanonicalValue)] = [
            ("coreURL", .string(coreURL)), ("trustMode", .string(trustMode.rawValue)),
            ("leafPin", .string(leafPin.hex)), ("datasetID", .string(datasetID.hex)),
            ("enrollmentID", .string(enrollmentID.hex)), ("token", .string(token.payloadText)),
            ("expiresAt", .integer(expiresAt)),
            ("coreSigningSPKI", .string(StrictBase64URL.encode(coreSigningKey.spkiDER))),
            ("coreSigningFingerprint", .string(coreSigningKey.fingerprint.hex)),
        ]
        if let caDigest { fields.append(("caDigest", .string(caDigest.hex))) }
        return try OwnerTextCodec.encode(prefix: Self.prefix, version: Self.version, fields: fields)
    }

    /// Decodes and validates a pairing text under the shared rule: size, prefix and version, strict base64url of a
    /// canonical object, checksum, no missing or unknown fields, and the signing key against its fingerprint.
    public static func decode(_ text: String) throws(TrustError) -> PairingText {
        var reader = try OwnerTextCodec.decode(
            text, prefix: prefix, version: version, outdatedPrefixes: outdatedPrefixes)
        do {
            let url = try reader.string("coreURL")
            guard let mode = TrustMode(rawValue: try reader.string("trustMode")) else {
                throw TrustError.invalidField("trustMode")
            }
            let leafPin = try digest(reader.string("leafPin"), "leafPin")
            let caDigest = try reader.optionalString("caDigest").map { (hex) throws(TrustError) in
                try digest(hex, "caDigest")
            }
            let dataset = try identifier(reader.string("datasetID"), "datasetID")
            let enrollment = try identifier(reader.string("enrollmentID"), "enrollmentID")
            let token = try EnrollmentToken(payloadText: reader.string("token"))
            let expiresAt = try reader.integer("expiresAt")
            let spki = try reader.bytes("coreSigningSPKI")
            let fingerprint = try digest(reader.string("coreSigningFingerprint"), "coreSigningFingerprint")
            try reader.finish()
            return try PairingText(
                coreURL: url, trustMode: mode, leafPin: leafPin, caDigest: caDigest, datasetID: dataset,
                enrollmentID: enrollment, token: token, expiresAt: expiresAt,
                coreSigningKey: CoreSigningIdentity(spkiDER: spki, fingerprint: fingerprint))
        } catch let error as TrustError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .payloadEncoding
        }
    }

    public var description: String {
        "PairingText(\(trustMode.rawValue), \(coreURL), enrollment \(enrollmentID), token redacted)"
    }

    /// An `https` URL with a host and, at most, a port and a root path: no credentials, query or fragment.
    static func isValidCoreURL(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), components.scheme == "https",
            let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil, components.path.isEmpty || components.path == "/"
        else { return false }
        return true
    }

    static func digest(_ hex: String, _ field: String) throws(TrustError) -> Digest256 {
        guard let value = try? Digest256(hex: hex) else { throw .invalidField(field) }
        return value
    }

    static func identifier(_ hex: String, _ field: String) throws(TrustError) -> Identifier128 {
        guard let value = try? Identifier128(hex: hex) else { throw .invalidField(field) }
        return value
    }
}
