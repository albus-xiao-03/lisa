// PROOF ONLY — Apps/Proof never ships. Generic-password items in the data-protection Keychain for the proof's
// synthetic values (device ID, operation key blob, Design A agreement key, the proof setup text), available after
// first unlock on this device only. Nothing here is a production credential (plan §8.7 X1; CONSTRICTION Security).

import Foundation
import Security

enum ProofKeychain {
    static let service = "org.example.lisa.proof"

    enum Failure: Error, Equatable {
        case status(OSStatus)
    }

    /// The item's data, or nil if there is none.
    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure.status(status) }
        return data
    }

    /// Adds a new item. A proof value is written once per installation and never replaced in place.
    static func add(_ account: String, _ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    /// Removes every proof generic-password item: the owner's explicit "reset proof identity" action only.
    static func removeAllProofItems() -> OSStatus {
        SecItemDelete(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecUseDataProtectionKeychain as String: true,
            ] as CFDictionary)
    }
}
