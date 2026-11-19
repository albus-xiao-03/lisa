// The Mac app's identity toward its host: a stable installation identifier kept in the app's defaults, and the owner
// credential of a running `lisa serve`, held in memory for this process only.

import Foundation
import LisaClient
import Synchronization

/// The credential store of the Mac app's one client (D-48, D-50). The app acts as the owner, never as a paired device.
///
/// - With the embedded host, the in-process owner transport authenticates the owner itself, so no credential is held.
/// - In client mode, the owner credential that `lisa serve` wrote to its owner endpoint file is held for as long as
///   this process uses that host, as the `lisa` commands hold it for one command. It is a secret: it is never written
///   to disk, described or logged, and a host that restarts issues a new one.
/// - The installation identifier is created once and kept in the app's defaults. It is not a secret. The request IDs
///   of notification actions and this Mac's local-notification installation on the host use it, so it stays the same
///   across launches.
final class MacOwnerCredentials: CredentialStore {
    private static let installationKey = "LisaInstallationID"

    private let identity: Mutex<ClientIdentity?>

    /// The store with the installation identifier saved by an earlier launch, if any.
    init() {
        let saved = UserDefaults.standard.string(forKey: Self.installationKey)
        identity = Mutex(saved.map { ClientIdentity(installationID: $0) })
    }

    /// This installation's identifier, created and saved on first use.
    var installationID: String {
        identity.withLock { current in
            if let existing = current { return existing.installationID }
            let created = ClientIdentity.newInstallation()
            UserDefaults.standard.set(created.installationID, forKey: Self.installationKey)
            current = created
            return created.installationID
        }
    }

    /// Holds the owner credential of the `lisa serve` this app connects to, or drops it with `nil`.
    func setOwnerCredential(_ credential: String?) {
        let installation = installationID
        identity.withLock { $0 = ClientIdentity(installationID: installation, credential: credential) }
    }

    /// Starts a new installation identifier and returns it, for a Mac whose local installation the owner removed from
    /// Lisa's devices: the host keeps a removed installation removed.
    func renewInstallationID() -> String {
        let created = ClientIdentity.newInstallation()
        UserDefaults.standard.set(created.installationID, forKey: Self.installationKey)
        identity.withLock { current in
            current = ClientIdentity(installationID: created.installationID, credential: current?.credential)
        }
        return created.installationID
    }

    func load() throws -> ClientIdentity? {
        identity.withLock { $0 }
    }

    func save(_ value: ClientIdentity) throws {
        UserDefaults.standard.set(value.installationID, forKey: Self.installationKey)
        identity.withLock { $0 = value }
    }

    func clear() throws {
        UserDefaults.standard.removeObject(forKey: Self.installationKey)
        identity.withLock { $0 = nil }
    }
}
