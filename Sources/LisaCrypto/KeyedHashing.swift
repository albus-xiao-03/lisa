// HKDF-SHA256 and HMAC-SHA256 over byte arrays (plan §7.2.2; §8.7 discovery tags and rejoin identities).

import Crypto
import Foundation

/// HKDF with SHA-256 (RFC 5869).
public enum HKDFSHA256 {
    /// Derives `outputByteCount` bytes (1 to 8,160) from the input keying material, salt and info.
    public static func deriveKey(
        inputKeyMaterial: [UInt8], salt: [UInt8], info: [UInt8], outputByteCount: Int
    ) throws(CryptoKeyError) -> [UInt8] {
        guard (1...(255 * 32)).contains(outputByteCount) else { throw .invalidOutputLength(outputByteCount) }
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial), salt: salt, info: info,
            outputByteCount: outputByteCount)
        return key.withUnsafeBytes { Array($0) }
    }
}

/// HMAC with SHA-256 (RFC 2104).
public enum HMACSHA256 {
    /// The 32-byte authentication code of `message` under `key`.
    public static func authenticationCode(for message: [UInt8], key: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    /// Whether `code` equals the leading `code.count` bytes (at least 16) of the authentication code of `message`,
    /// compared in constant time. Truncated codes are how discovery tags and rejoin identities travel (§8.7).
    public static func isValid(_ code: [UInt8], for message: [UInt8], key: [UInt8]) -> Bool {
        guard (16...32).contains(code.count) else { return false }
        let full = authenticationCode(for: message, key: key)
        return Digests.constantTimeEquals(Data(full.prefix(code.count)), Data(code))
    }
}
