// Test-only. The host's real network server (LisaHost's HostAPIServer over LisaAPIServer) on loopback for a test host:
// the device listener on 127.0.0.1 with plain HTTP, as API-01 allows there, on a free port or on the port of an
// earlier run (so a restarted host is reachable at the same address), plus the owner listener with its run
// credential. Clients reach it through the companions' URLSession transport and the CLI's libcurl transport. Used by
// the network suites (L10, L20, L21, L30) and later device suites.

import Foundation
import LisaAPIServer
import LisaClient
import LisaHost

/// A running loopback server for one host.
struct LoopbackAPIServer: Sendable {
    /// Why the server did not report the listeners it was asked for.
    struct MissingListener: Error, CustomStringConvertible {
        var description: String { "the server did not bind both the device and the owner listener" }
    }

    let server: HostAPIServer
    /// The owner credential issued for this run only.
    let ownerCredential: String
    /// The device listener's port on 127.0.0.1.
    let devicePort: Int
    /// The owner listener's port on 127.0.0.1.
    let ownerPort: Int

    /// Device-listener settings on 127.0.0.1 with plain HTTP; port 0 picks a free port.
    static func settings(port: Int = 0) -> APIServerSettings {
        APIServerSettings(bindAddress: "127.0.0.1", port: port, protection: .none)
    }

    /// Starts serving `host` as `lisa serve` does, on the device listener its settings name and an owner listener.
    static func start(for host: LisaHost) async throws -> LoopbackAPIServer {
        let (server, credential) = try await HostAPIServer.start(for: host)
        guard let devices = server.listeners.first(where: { $0.role == .devices }), let owner = server.ownerPort else {
            await server.stop()
            throw MissingListener()
        }
        return LoopbackAPIServer(
            server: server, ownerCredential: credential, devicePort: devices.port, ownerPort: owner)
    }

    /// The device listener's address, as a companion is configured with it.
    func endpoint() throws -> HostEndpoint {
        try HostEndpoint(parsing: "http://127.0.0.1:\(devicePort)")
    }

    /// A companion's URLSession transport to the device listener.
    func deviceTransport() throws -> URLSessionTransport {
        try URLSessionTransport(
            endpoint: endpoint(), configuration: URLSessionTransportConfiguration(requestTimeout: .seconds(20)))
    }

    /// The owner's client over the owner listener, as the CLI in client mode.
    func ownerClient() throws -> LisaAPIClient {
        try OwnerClient.loopback(port: ownerPort, credential: ownerCredential)
    }

    /// Stops serving: requests in progress finish within the grace period, then the owner credential is revoked.
    func stop() async {
        await server.stop()
    }
}
