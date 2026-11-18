// The client fallback (ARCH-03): when a running `lisa serve` owns the data directory, the app reaches that host's
// loopback owner listener through its owner endpoint file, exactly as the `lisa` commands do.

import Foundation
import LisaClient
import LisaHost
import LisaRuntime

/// A connection to the `lisa serve` that owns the data directory.
///
/// It follows `HostSession.connectedClient`: the owner endpoint file must be readable and owner-only, and it must belong
/// to the process that holds the data-directory lock, so a file left by an earlier run is never used. Requests then go
/// to `127.0.0.1` through libcurl (`LoopbackOwnerTransport`) with the owner credential that host issued for this run.
struct ServeClientConnection: Sendable {
    /// Why the app cannot connect to the runtime that owns the data directory.
    struct Refusal: Error, CustomStringConvertible {
        let description: String
    }

    /// The transport to the owner listener.
    let transport: LoopbackOwnerTransport
    /// The owner credential of this run of `lisa serve`. It is a secret, never shown or logged.
    let credential: String
    /// The serving process, which holds the data-directory lock.
    let processID: Int32
    /// When that process took the data directory.
    let since: Date
    /// The owner listener's port on 127.0.0.1.
    let port: Int

    /// Connects to `owner`, the runtime that holds the lock on `settings`' data directory.
    static func connect(settings: HostSettings, platform: HostPlatform, owner: LockOwner?) throws(Refusal)
        -> ServeClientConnection
    {
        let runtime = owner.map { "Lisa (\($0.mode), process \($0.processID))" } ?? "Another Lisa runtime"
        let endpoint: OwnerEndpoint?
        do {
            endpoint = try OwnerEndpointFile(dataDirectory: settings.dataDirectory).read()
        } catch {
            throw Refusal(
                description: "\(runtime) is using your data, and its owner endpoint can't be read: \(error)")
        }
        guard let endpoint, let owner, owner.processID == endpoint.processID else {
            throw Refusal(
                description: "\(runtime) is using your data and doesn't serve the network API, so this app can't "
                    + "connect to it. Try again when it has finished.")
        }
        let transport: LoopbackOwnerTransport
        do throws(HostError) {
            transport = try LoopbackOwnerTransport(port: endpoint.port, network: platform.network)
        } catch {
            throw Refusal(description: error.description)
        }
        return ServeClientConnection(
            transport: transport, credential: endpoint.credential, processID: endpoint.processID,
            since: owner.acquiredAt, port: endpoint.port)
    }
}
