// Test-only. An in-memory client identity store for API clients that keep nothing on disk: the local owner's
// in-process client and the CLI's client mode, which holds a run's owner credential for one command. Used by the API
// and client suites (L10, L20, L21, L30) and later device suites.

import Foundation
import LisaClient
import Synchronization

/// Keeps one client identity in memory. It stands in for the CLI's session credentials only; it is never presented as
/// Keychain or as the file store.
final class MemoryCredentialStore: CredentialStore {
    private let identity: Mutex<ClientIdentity?>

    /// - Parameter credential: a credential every request presents, such as a run's owner credential; none by default.
    init(credential: String? = nil) {
        identity = Mutex(ClientIdentity(installationID: "synthetic-owner-session", credential: credential))
    }

    func load() throws -> ClientIdentity? {
        identity.withLock { $0 }
    }

    func save(_ value: ClientIdentity) throws {
        identity.withLock { $0 = value }
    }

    func clear() throws {
        identity.withLock { $0 = nil }
    }
}
