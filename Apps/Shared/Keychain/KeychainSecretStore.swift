// The Mac's embedded host resolves keychain:service/account secret references from this app's Keychain items. Only
// the Mac app runs a host and links LisaSecrets, so the companion compiles this file empty.

#if os(macOS)
    import Foundation
    import LisaRedaction
    import LisaSecrets

    /// Resolves `keychain:service/account` references for the Mac app's embedded host (SEC-01, D-08), such as the
    /// APNs signing key, a mailbox password or a model key.
    ///
    /// - A reference `keychain:<service>/<account>` is the generic-password item of the service
    ///   `<bundle identifier>.secrets.<service>` and the account `<account>`, holding the secret as UTF-8 text of at
    ///   most 64 KiB.
    /// - Items are available after first unlock on this device only, never synchronized, and kept in the data
    ///   protection keychain (`KeychainItemAccess`). Items that other tools put in the file-based login keychain are
    ///   not read; the owner stores secrets through `save(_:for:)` in the app.
    /// - Failures are `SecretStoreError` values that name the reference and the Keychain status, never the secret.
    ///   Other reference kinds are `unsupported`; `CompositeSecretStore` routes them to their own stores.
    struct KeychainSecretStore: SecretStore {
        /// The largest secret accepted, as for the other secret stores.
        static let maxSecretBytes = 65_536

        private let bundleIdentifier: String

        /// The secrets of the app with `bundleIdentifier`.
        init(bundleIdentifier: String) {
            self.bundleIdentifier = bundleIdentifier
        }

        /// The secrets of this app.
        static func forThisApp() throws -> KeychainSecretStore {
            KeychainSecretStore(bundleIdentifier: try ThisAppBuild.requiredBundleIdentifier())
        }

        func secret(for reference: SecretReference) throws -> Sensitive<String> {
            guard case .keychain(let service, let account) = reference else {
                throw SecretStoreError.unsupported(reference.description)
            }
            let stored: Data?
            do throws(KeychainItemError) {
                stored = try item(service).read(account: account)
            } catch {
                throw SecretStoreError.unreadable("\(reference.description) (\(error.description))")
            }
            guard let stored else { throw SecretStoreError.notFound(reference.description) }
            guard stored.count <= Self.maxSecretBytes else { throw SecretStoreError.tooLarge(reference.description) }
            guard let value = String(data: stored, encoding: .utf8), !value.isEmpty else {
                throw SecretStoreError.unreadable(reference.description)
            }
            return Sensitive(value)
        }

        /// Stores `value` as the secret `reference` names, replacing any earlier value.
        ///
        /// - Throws: `SecretStoreError.unsupported` for a reference that is not `keychain:`, `.tooLarge` or
        ///   `.notFound` for a secret over 64 KiB or empty, and `KeychainItemError` when Keychain refuses it.
        func save(_ value: Sensitive<String>, for reference: SecretReference) throws {
            guard case .keychain(let service, let account) = reference else {
                throw SecretStoreError.unsupported(reference.description)
            }
            let data = Data(value.revealed.utf8)
            guard !data.isEmpty else { throw SecretStoreError.notFound(reference.description) }
            guard data.count <= Self.maxSecretBytes else { throw SecretStoreError.tooLarge(reference.description) }
            try item(service).write(data, account: account)
        }

        /// Removes the secret `reference` names; a missing one is not an error.
        func remove(_ reference: SecretReference) throws {
            guard case .keychain(let service, let account) = reference else {
                throw SecretStoreError.unsupported(reference.description)
            }
            try item(service).delete(account: account)
        }

        private func item(_ service: String) -> KeychainItemAccess {
            KeychainItemAccess(service: KeychainServiceName.secret(service, bundleIdentifier: bundleIdentifier))
        }
    }
#endif
