// Generic-password Keychain items of one service: read, replace and delete. Available after first unlock, on this
// device only, never synchronized, and in the data protection keychain on the Mac.

import Foundation
import Security

/// The generic-password items of one Keychain service (SEC-01).
///
/// - Every item is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: once the device has been unlocked after a
///   restart it stays readable while locked, so notification actions taken on the lock screen can authenticate
///   (plan §6.5). It is never migrated to another device.
/// - Items are never synchronizable, so they never reach iCloud Keychain.
/// - On the Mac every call uses the data protection keychain (`kSecUseDataProtectionKeychain`), which behaves as on
///   iPhone and iPad. It requires the app to be signed with a provisioning profile; without one, calls fail with
///   `errSecMissingEntitlement` and nothing falls back to the file-based keychain.
struct KeychainItemAccess: Sendable {
    /// The service the items belong to.
    let service: String

    /// The data of the item for `account`, or `nil` when there is none.
    func read(account: String) throws(KeychainItemError) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainItemError(status: status) }
        guard let data = result as? Data else { throw KeychainItemError(status: errSecDecode) }
        return data
    }

    /// Stores `data` for `account`, replacing any earlier value and setting the accessibility class again.
    func write(_ data: Data, account: String) throws(KeychainItemError) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if try update(query, attributes) { return }
        let item = query.merging(attributes) { _, new in new }
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecSuccess { return }
        // Another writer added the item meanwhile: replace its value instead.
        guard added == errSecDuplicateItem, try update(query, attributes) else {
            throw KeychainItemError(status: added)
        }
    }

    /// Removes the item for `account`; a missing item is not an error.
    func delete(account: String) throws(KeychainItemError) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainItemError(status: status) }
    }

    /// Updates the item matching `query`; `false` when there is none.
    private func update(_ query: [String: Any], _ attributes: [String: Any]) throws(KeychainItemError) -> Bool {
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw KeychainItemError(status: status) }
        return true
    }

    /// The attributes that identify the item for `account`: generic password, this service, never synchronizable,
    /// and on the Mac the data protection keychain.
    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        #if os(macOS)
            query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}
