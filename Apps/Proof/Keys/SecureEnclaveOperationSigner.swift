// PROOF ONLY — Apps/Proof never ships. The device's operation key in the Secure Enclave, signing nearby
// authentication transcripts (plan §8.7) through LisaTrust's `MessageSigning` boundary (plan §7.2.3).

import CryptoKit
import Foundation
import LisaCrypto
import LisaTrust
import Security

/// Signs with a CryptoKit Secure Enclave P-256 key. Only the key's opaque, device-bound `dataRepresentation` is
/// held (a `Sendable` value); the enclave key is reopened for each signature.
struct SecureEnclaveOperationSigner: MessageSigning {
    let keyData: Data
    let verifier: P256Verifier

    init(keyData: Data) throws {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData)
        self.keyData = keyData
        verifier = try P256Verifier(canonicalSPKI: Array(key.publicKey.derRepresentation))
    }

    /// A new enclave key usable after first unlock on this device only.
    static func createKeyData() throws -> Data {
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error)
        else { throw error?.takeRetainedValue() ?? ProofKeychain.Failure.status(errSecParam) }
        return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access).dataRepresentation
    }

    func rawSignature(for message: [UInt8]) throws -> [UInt8] {
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData)
        return Array(try key.signature(for: Data(message)).rawRepresentation)
    }
}
