// PROOF ONLY — Apps/Proof never ships. This installation's synthetic proof identity: a random device ID, the
// operation key (Secure Enclave where available, otherwise a software key, recorded as such), and Design A's
// agreement key. It is introduced to peers only through the proof roster texts, never through enrollment (§8.1).

import CryptoKit
import Foundation
import LisaCrypto
import LisaSyncProtocol
import LisaTrust

struct ProofDeviceKeys: Sendable {
    enum OperationKeyStorage: String, Codable, Sendable {
        case secureEnclave = "secure-enclave"
        case softwareKeychain = "software-keychain"
        case ephemeralUnenrolled = "ephemeral-unenrolled"
    }

    let deviceID: Identifier128
    let operationSigner: any MessageSigning
    let operationKeyStorage: OperationKeyStorage
    /// A software key whose raw scalar sits in the Keychain. Production keeps the agreement key in the Secure
    /// Enclave, which needs a portable agreement boundary first (docs/DECISIONS.md D-54).
    let agreementKey: P256AgreementKey

    static let deviceIDAccount = "device-id"
    static let enclaveOperationAccount = "operation-key-se"
    static let softwareOperationAccount = "operation-key-sw"
    static let agreementAccount = "agreement-key"

    /// Loads the identity, creating each missing part once.
    static func loadOrCreate() throws -> ProofDeviceKeys {
        let deviceID: Identifier128
        if let stored = try ProofKeychain.read(deviceIDAccount) {
            deviceID = try Identifier128(bytes: Array(stored))
        } else {
            deviceID = Identifier128.random()
            try ProofKeychain.add(deviceIDAccount, Data(deviceID.bytes))
        }
        let signer: any MessageSigning
        let storage: OperationKeyStorage
        if let blob = try ProofKeychain.read(enclaveOperationAccount) {
            signer = try SecureEnclaveOperationSigner(keyData: blob)
            storage = .secureEnclave
        } else if let raw = try ProofKeychain.read(softwareOperationAccount) {
            signer = try P256RawSigner(rawPrivateKey: Array(raw))
            storage = .softwareKeychain
        } else if SecureEnclave.isAvailable {
            let blob = try SecureEnclaveOperationSigner.createKeyData()
            try ProofKeychain.add(enclaveOperationAccount, blob)
            signer = try SecureEnclaveOperationSigner(keyData: blob)
            storage = .secureEnclave
        } else {
            let software = P256RawSigner()
            try ProofKeychain.add(softwareOperationAccount, Data(software.rawPrivateKey))
            signer = software
            storage = .softwareKeychain
        }
        let agreement: P256AgreementKey
        if let raw = try ProofKeychain.read(agreementAccount) {
            agreement = try P256AgreementKey(rawPrivateKey: Array(raw))
        } else {
            agreement = P256AgreementKey()
            try ProofKeychain.add(agreementAccount, Data(agreement.rawPrivateKey))
        }
        return ProofDeviceKeys(
            deviceID: deviceID, operationSigner: signer, operationKeyStorage: storage, agreementKey: agreement)
    }

    /// A throwaway identity that no roster lists, for the "unenrolled identity is refused" cases. Kept in memory
    /// only and discarded after the attempt.
    static func unenrolled() -> ProofDeviceKeys {
        ProofDeviceKeys(
            deviceID: Identifier128.random(), operationSigner: P256RawSigner(),
            operationKeyStorage: .ephemeralUnenrolled, agreementKey: P256AgreementKey())
    }

    /// The same device ID and agreement key with a fresh, unenrolled operation key: TLS succeeds and the session
    /// layer must refuse the signature (the second unenrolled-identity case).
    func withUnenrolledOperationKey() -> ProofDeviceKeys {
        ProofDeviceKeys(
            deviceID: deviceID, operationSigner: P256RawSigner(), operationKeyStorage: .ephemeralUnenrolled,
            agreementKey: agreementKey)
    }
}
