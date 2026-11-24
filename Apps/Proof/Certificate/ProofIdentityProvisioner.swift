// PROOF ONLY — Apps/Proof never ships. Design B's identity at X1 (plan §8.7, "X1, proof-only provisioning"): the
// Secure Enclave TLS key, a certificate from the fixed-template encoder, the certificate added to the Keychain beside
// the key so that Security pairs them into a `SecIdentity`, and `sec_identity_create` for Network framework. Each
// step's outcome is recorded, because forming the identity is itself part of what X1 observes. The unenrolled slot
// forms a second identity the same way; its pin is never put into a card.

import Foundation
import LisaCrypto
import LisaSyncProtocol
import Network
import Security

struct ProofIdentityProvisioner {
    static func certificateLabel(_ slot: SecureEnclaveTLSKey.Slot) -> String {
        switch slot {
        case .enrolled: "Lisa proof-only TLS certificate"
        case .unenrolled: "Lisa proof-only TLS certificate (unenrolled)"
        }
    }

    struct Provisioned: @unchecked Sendable {
        let identity: sec_identity_t
        /// SHA-256 of the canonical SPKI: the Design B pin that goes into this device's proof card.
        let spkiSHA256: Digest256
        /// Step name → observation, copied into the result's evidence.
        let steps: [String: String]
    }

    enum Failure: Error {
        case step(String, [String: String])
    }

    static func provision(_ slot: SecureEnclaveTLSKey.Slot = .enrolled) throws -> Provisioned {
        var steps: [String: String] = ["slot": slot.rawValue]
        let key: SecureEnclaveTLSKey
        do {
            key = try SecureEnclaveTLSKey.loadOrCreate(slot)
            steps["secure-enclave-key"] = "ok"
        } catch {
            steps["secure-enclave-key"] = "failed: \(error)"
            throw Failure.step("secure-enclave-key", steps)
        }
        let spki = ProofCertificateEncoder.p256SPKIPrefix + key.publicKeyX963
        guard let verifier = try? P256Verifier(canonicalSPKI: spki),
            let pin = try? Digest256(bytes: verifier.fingerprint)
        else {
            steps["spki"] = "not a canonical P-256 key"
            throw Failure.step("spki", steps)
        }
        if let identity = try copyIdentity(slot) {
            steps["identity"] = "existing SecIdentity found"
            return try wrap(identity, pin: pin, steps: steps)
        }
        let certificate: ProofCertificate
        do {
            certificate = try ProofCertificateEncoder.certificate(signer: key, notBefore: Date())
            steps["certificate-encoded"] = "serial \(LowercaseHexText.encode(certificate.serial))"
        } catch {
            steps["certificate-encoded"] = "failed: \(error)"
            throw Failure.step("certificate-encoded", steps)
        }
        guard let secCertificate = SecCertificateCreateWithData(nil, Data(certificate.der) as CFData) else {
            steps["certificate-parsed"] = "SecCertificateCreateWithData refused the DER"
            throw Failure.step("certificate-parsed", steps)
        }
        steps["certificate-parsed"] = "ok"
        let status = SecItemAdd(
            [
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: secCertificate,
                kSecAttrLabel as String: certificateLabel(slot),
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary, nil)
        steps["certificate-added"] = "status \(status)"
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw Failure.step("certificate-added", steps)
        }
        guard let identity = try copyIdentity(slot) else {
            steps["identity"] = "Security formed no SecIdentity for the key and certificate"
            throw Failure.step("identity", steps)
        }
        steps["identity"] = "SecIdentity formed"
        return try wrap(identity, pin: pin, steps: steps)
    }

    /// The identity whose private key carries the slot's application tag.
    static func copyIdentity(_ slot: SecureEnclaveTLSKey.Slot) throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrApplicationTag as String: slot.applicationTag,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result else { throw Failure.step("identity-lookup \(status)", [:]) }
        return (result as! SecIdentity)
    }

    static func wrap(_ identity: SecIdentity, pin: Digest256, steps: [String: String]) throws -> Provisioned {
        var steps = steps
        guard let wrapped = sec_identity_create(identity) else {
            steps["sec-identity-create"] = "returned nil"
            throw Failure.step("sec-identity-create", steps)
        }
        steps["sec-identity-create"] = "ok"
        return Provisioned(identity: wrapped, spkiSHA256: pin, steps: steps)
    }
}
