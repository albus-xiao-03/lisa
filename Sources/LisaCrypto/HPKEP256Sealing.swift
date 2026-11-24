// HPKE base mode with the P256_SHA256_AES_GCM_256 suite (RFC 9180), for sealing to export keys (plan §8.6.6).

import Crypto
import Foundation

/// One HPKE-sealed message: the sender's encapsulated key and the ciphertext with its tag.
public struct HPKESealedMessage: Hashable, Sendable {
    public let encapsulatedKey: [UInt8]
    public let ciphertext: [UInt8]

    public init(encapsulatedKey: [UInt8], ciphertext: [UInt8]) {
        self.encapsulatedKey = encapsulatedKey
        self.ciphertext = ciphertext
    }
}

/// Single-shot HPKE sealing to a P-256 recipient key and opening with its private key.
public enum HPKEP256 {
    /// Seals `plaintext` to `recipient`, binding `info` (the context) and `authenticatedData`.
    public static func seal(
        _ plaintext: [UInt8], to recipient: P256AgreementPublicKey, info: [UInt8], authenticatedData: [UInt8]
    ) throws(CryptoKeyError) -> HPKESealedMessage {
        do {
            var sender = try HPKE.Sender(
                recipientKey: recipient.key, ciphersuite: .P256_SHA256_AES_GCM_256, info: Data(info))
            let ciphertext = try sender.seal(plaintext, authenticating: authenticatedData)
            return HPKESealedMessage(encapsulatedKey: Array(sender.encapsulatedKey), ciphertext: Array(ciphertext))
        } catch {
            throw .sealFailed
        }
    }

    /// Opens a message sealed to `key`'s public half with the same `info` and `authenticatedData`.
    /// - Throws: `CryptoKeyError.openFailed` for a wrong key, a wrong context or altered bytes.
    public static func open(
        _ message: HPKESealedMessage, with key: P256AgreementKey, info: [UInt8], authenticatedData: [UInt8]
    ) throws(CryptoKeyError) -> [UInt8] {
        do {
            var recipient = try HPKE.Recipient(
                privateKey: key.key, ciphersuite: .P256_SHA256_AES_GCM_256, info: Data(info),
                encapsulatedKey: Data(message.encapsulatedKey))
            return Array(try recipient.open(message.ciphertext, authenticating: authenticatedData))
        } catch {
            throw .openFailed
        }
    }
}
