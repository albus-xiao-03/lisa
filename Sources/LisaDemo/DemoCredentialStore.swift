// In-memory pairing identities for the demonstration's synthetic devices; nothing is written anywhere.

import Foundation
import LisaClient
import Synchronization

/// Keeps one synthetic device's identity in memory for the length of the demonstration.
final class DemoCredentialStore: CredentialStore {
    private let identity: Mutex<ClientIdentity?>

    init(installationID: String) {
        identity = Mutex(ClientIdentity(installationID: installationID))
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
