// AES-256-GCM with a 96-bit nonce and authenticated data, for the protected archive's payload (plan §8.6.6).

import Crypto
import Foundation

/// AES-256-GCM sealing and opening over byte arrays. The sealed form is `ciphertext ‖ 16-byte tag`.
public enum AESGCM256 {
    public static let keyLength = 32
    public static let nonceLength = 12
    public static let tagLength = 16

    /// A new random 256-bit key.
    public static func randomKey() -> [UInt8] { [UInt8](RandomTokens.bytes(keyLength)) }

    /// A new random 96-bit nonce.
    public static func randomNonce() -> [UInt8] { [UInt8](RandomTokens.bytes(nonceLength)) }

    /// Encrypts and authenticates `plaintext` with `authenticatedData`.
    public static func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8], authenticatedData: [UInt8])
        throws(CryptoKeyError) -> [UInt8]
    {
        guard key.count == keyLength, nonce.count == nonceLength, let gcmNonce = try? AES.GCM.Nonce(data: nonce),
            let box = try? AES.GCM.seal(
                plaintext, using: SymmetricKey(data: key), nonce: gcmNonce, authenticating: authenticatedData)
        else { throw .sealFailed }
        return Array(box.ciphertext) + Array(box.tag)
    }

    /// Opens `sealed` (`ciphertext ‖ tag`).
    /// - Throws: `CryptoKeyError.openFailed` for a wrong key, nonce or authenticated data, or altered bytes.
    public static func open(_ sealed: [UInt8], key: [UInt8], nonce: [UInt8], authenticatedData: [UInt8])
        throws(CryptoKeyError) -> [UInt8]
    {
        guard key.count == keyLength, nonce.count == nonceLength, sealed.count >= tagLength,
            let gcmNonce = try? AES.GCM.Nonce(data: nonce),
            let box = try? AES.GCM.SealedBox(
                nonce: gcmNonce, ciphertext: sealed.dropLast(tagLength), tag: sealed.suffix(tagLength)),
            let plaintext = try? AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: authenticatedData)
        else { throw .openFailed }
        return Array(plaintext)
    }
}
