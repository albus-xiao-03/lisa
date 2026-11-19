// Test-only. Typed API clients that act as the local owner: in process, as the Mac app's embedded host, the CLI and
// the demo do, and over the loopback owner listener with a run's owner credential, as the CLI does in client mode.
// Used by the API and client suites (L10, L20, L21, L30) and later device suites.

import Foundation
import LisaClient
import LisaHost

/// The local owner's typed clients.
enum OwnerClient {
    /// The owner's client over the host's in-process transport, which trusts its caller as the local owner; no
    /// credential is involved.
    static func inProcess(_ host: LisaHost) -> LisaAPIClient {
        LisaAPIClient(transport: host.ownerTransport, credentials: MemoryCredentialStore(), requiresPairing: false)
    }

    /// The owner's client over the loopback owner listener on `port`, presenting `credential` through the CLI's
    /// libcurl transport (127.0.0.1 only, never through a proxy).
    static func loopback(port: Int, credential: String) throws -> LisaAPIClient {
        let transport = try LoopbackOwnerTransport(port: port, network: .libcurl(userAgent: "lisa-tests"))
        return LisaAPIClient(
            transport: transport, credentials: MemoryCredentialStore(credential: credential), requiresPairing: false)
    }
}
