// PROOF ONLY — Apps/Proof never ships. Design B's TLS key (plan §8.7): a permanent P-256 key in the Secure Enclave,
// created through Security as a Keychain `SecKey` (kSecAttrTokenIDSecureEnclave, kSecAttrIsPermanent), and the
// certificate encoder's signing step through `SecKeyCreateSignature` (ECDSA, X9.62 DER, SHA-256 of the message).
//
// §8.7 says the proof encoder signs "through CryptoKit". A CryptoKit `SecureEnclave.P256.Signing.PrivateKey` is not a
// Keychain item, so Security cannot pair a certificate with it into a `SecIdentity`; a Keychain-resident Secure
// Enclave `SecKey` can, which is also the X4 path §8.7 names (docs/DECISIONS.md D-54).
//
// Two slots: the enrolled key, whose pin goes into this device's proof card, and a throwaway key that no roster ever
// lists, which Design B's unenrolled-identity fault presents so that the peer's verify block must refuse it.

import Foundation
import Security

struct SecureEnclaveTLSKey: ProofCertificateSigning {
    enum Slot: String, Sendable, CaseIterable {
        case enrolled
        case unenrolled

        var applicationTag: Data {
            switch self {
            case .enrolled: Data("org.example.lisa.proof.tls-key".utf8)
            case .unenrolled: Data("org.example.lisa.proof.tls-key.unenrolled".utf8)
            }
        }
    }

    enum Failure: Error {
        case security(String)
    }

    let key: SecKey
    let publicKeyX963: [UInt8]

    init(key: SecKey) throws {
        guard let publicKey = SecKeyCopyPublicKey(key) else { throw Failure.security("no public key") }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw Failure.security(String(describing: error?.takeRetainedValue()))
        }
        self.key = key
        publicKeyX963 = Array(data)
    }

    /// The slot's existing key, or a new one usable after first unlock on this device only.
    static func loadOrCreate(_ slot: Slot) throws -> SecureEnclaveTLSKey {
        if let existing = try find(slot) { return try SecureEnclaveTLSKey(key: existing) }
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error)
        else { throw Failure.security(String(describing: error?.takeRetainedValue())) }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecUseDataProtectionKeychain as String: true,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: slot.applicationTag,
                kSecAttrAccessControl as String: access,
            ] as [String: Any],
        ]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw Failure.security(String(describing: error?.takeRetainedValue()))
        }
        return try SecureEnclaveTLSKey(key: key)
    }

    static func find(_ slot: Slot) throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: slot.applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result else { throw Failure.security("key lookup status \(status)") }
        return (result as! SecKey)
    }

    func ecdsaSHA256SignatureDER(over message: [UInt8]) throws -> [UInt8] {
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                key, .ecdsaSignatureMessageX962SHA256, Data(message) as CFData, &error) as Data?
        else { throw Failure.security(String(describing: error?.takeRetainedValue())) }
        return Array(signature)
    }
}
