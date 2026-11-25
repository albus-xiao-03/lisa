// Credential reset (plan §8.1.4): the one-time reset token and its one hash function, and the device's request signed
// by its existing operation key.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// A 32-byte one-time reset token, shown once to the owner. Core stores only `tokenHash`; `description` never shows
/// the bytes.
public struct CredentialResetToken: Hashable, Sendable, CustomStringConvertible {
    public static let byteCount = 32
    static let hashLabel = Array("lisa-reset-token-v1".utf8)

    public let bytes: [UInt8]

    /// - Throws: `TrustError.invalidToken` unless `bytes` has exactly 32 bytes.
    public init(bytes: [UInt8]) throws(TrustError) {
        guard bytes.count == Self.byteCount else { throw .invalidToken }
        self.bytes = bytes
    }

    /// The token as the owner enters it: unpadded base64url; any other length or spelling is refused.
    public init(text: String) throws(TrustError) {
        guard let decoded = try? StrictBase64URL.decode(text) else { throw .invalidToken }
        try self.init(bytes: decoded)
    }

    public static func random() -> CredentialResetToken {
        // Thirty-two random bytes always make a token.
        try! CredentialResetToken(bytes: [UInt8](RandomTokens.bytes(byteCount)))
    }

    public var text: String { StrictBase64URL.encode(bytes) }

    /// `SHA-256(ASCII "lisa-reset-token-v1" ‖ 0x00 ‖ token)`, the same at issuance and verification.
    public var tokenHash: [UInt8] { [UInt8](Digests.sha256(Data(Self.hashLabel + [0x00] + bytes))) }

    public var description: String { "CredentialResetToken(redacted)" }
}

/// Why a reset request was refused before Core looked at its token.
public enum CredentialResetVerificationError: Error, Hashable, Sendable {
    case malformed(OperationEnvelopeError)
    case invalidSignature
}

/// Signs and verifies credential-reset requests.
public enum CredentialResetSigning {
    public static func sign(_ request: CredentialResetRequest, with operationKey: some MessageSigning) throws
        -> SignedBody
    {
        let body = try request.canonicalBody()
        return try SignedBody(
            body: body, signature: try DomainSignatures.sign(body, domain: .credentialReset, with: operationKey),
            maximumBytes: CredentialResetRequest.maximumBytes)
    }

    /// The request, only if `key`, the device's existing operation key, signed these exact bytes.
    public static func verify(_ signed: SignedBody, key: P256Verifier) throws(CredentialResetVerificationError)
        -> CredentialResetRequest
    {
        guard DomainSignatures.isValid(signed.signature, over: signed.body, domain: .credentialReset, by: key) else {
            throw .invalidSignature
        }
        do {
            return try CredentialResetRequest.decode(body: signed.body)
        } catch {
            throw .malformed(error)
        }
    }
}
