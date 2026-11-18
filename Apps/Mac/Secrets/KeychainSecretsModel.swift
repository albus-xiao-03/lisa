// The `keychain:` secret references in the owner's configuration, whether this app's Keychain holds each one, and
// storing or removing them, so that the embedded host can resolve them (SEC-01, D-48).

import Foundation
import LisaConfig
import LisaRedaction
import LisaSecrets
import Observation

/// The configuration's `keychain:service/account` secrets (SEC-01).
///
/// The embedded host resolves them from this app's data-protection Keychain items (`KeychainSecretStore`), which only
/// this app can write, so the owner stores them here. A secret is never shown again once stored: the screen says only
/// whether it is set. Secrets are read when the host starts, so a change takes effect after the host restarts. `lisa
/// serve` and the `lisa` commands have no Keychain store and report `keychain:` references as unsupported.
@MainActor
@Observable
final class KeychainSecretsModel {
    /// One referenced secret.
    struct Entry: Hashable, Identifiable {
        /// Whether the Keychain holds the secret.
        enum State: Hashable {
            case stored
            case missing
            /// It could not be read; the message names the reference and the Keychain status, never a value.
            case unreadable(String)
        }

        /// The reference, which names a location, never a value.
        let reference: SecretReference
        /// The settings that use it, such as `notifications.apns.signingKeySecret`.
        let settings: [String]
        /// Whether the Keychain holds it.
        let state: State

        var id: String { reference.description }
    }

    /// The configuration's `keychain:` secrets, in reference order.
    private(set) var entries: [Entry] = []
    /// Whether a secret changed since the host last started.
    private(set) var changedSinceStart = false
    /// Why the latest change did not work, if it did not.
    private(set) var problem: String?

    @ObservationIgnored private let keychain: KeychainSecretStore?
    @ObservationIgnored private var configuration: LisaConfiguration?

    /// The secrets of this app, or none without a bundle identifier.
    init() {
        keychain = try? KeychainSecretStore.forThisApp()
    }

    /// The largest secret accepted.
    static let maxSecretBytes = KeychainSecretStore.maxSecretBytes

    /// Lists the `keychain:` secrets `configuration` refers to and whether each is stored.
    func load(_ configuration: LisaConfiguration?) {
        self.configuration = configuration
        reload()
    }

    /// Notes that the host started again, so it read the secrets as they are now.
    func hostStarted() {
        changedSinceStart = false
    }

    /// Stores `value` as the secret `reference` names, replacing any earlier one. Returns whether it was stored.
    @discardableResult
    func save(_ value: String, for reference: SecretReference) -> Bool {
        guard let keychain else {
            problem = "this app has no bundle identifier, so it can't name its Keychain items"
            return false
        }
        do {
            try keychain.save(Sensitive(value), for: reference)
        } catch {
            problem = "the secret \(reference) was not stored: \(error)"
            return false
        }
        problem = nil
        changedSinceStart = true
        reload()
        return true
    }

    /// Removes the secret `reference` names. Returns whether it is gone.
    @discardableResult
    func remove(_ reference: SecretReference) -> Bool {
        guard let keychain else { return false }
        do {
            try keychain.remove(reference)
        } catch {
            problem = "the secret \(reference) was not removed: \(error)"
            return false
        }
        problem = nil
        changedSinceStart = true
        reload()
        return true
    }

    /// Reads which secrets are stored. Each one is read and dropped at once; nothing keeps or shows its value.
    private func reload() {
        var settingsByReference: [SecretReference: [String]] = [:]
        var order: [SecretReference] = []
        for secret in configuration?.referencedSecrets ?? [] {
            guard case .keychain = secret.reference else { continue }
            if settingsByReference[secret.reference] == nil { order.append(secret.reference) }
            settingsByReference[secret.reference, default: []].append(secret.path)
        }
        entries = order.map { reference in
            Entry(reference: reference, settings: settingsByReference[reference] ?? [], state: state(of: reference))
        }
    }

    private func state(of reference: SecretReference) -> Entry.State {
        guard let keychain else { return .unreadable("this app has no bundle identifier") }
        do {
            _ = try keychain.secret(for: reference)
            return .stored
        } catch let error as SecretStoreError {
            if case .notFound = error { return .missing }
            return .unreadable(error.description)
        } catch {
            return .unreadable("\(error)")
        }
    }
}
