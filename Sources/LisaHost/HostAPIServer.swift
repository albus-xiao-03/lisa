// The host's network server (plan §5.2, step 10): the configured device listener for paired devices, plus a loopback
// owner listener on a free port for the CLI in client mode. Both go through the host's one router.

import Foundation
import LisaAPI
import LisaAPIContract
import LisaAPIServer
import LisaSecrets

/// A running network server and what local clients need to reach it.
public final class HostAPIServer: Sendable {
    let server: APIServer
    let ownerAccess: OwnerAccess
    /// The listeners actually bound.
    public let listeners: [BoundAPIListener]

    private init(server: APIServer, ownerAccess: OwnerAccess, listeners: [BoundAPIListener]) {
        self.server = server
        self.ownerAccess = ownerAccess
        self.listeners = listeners
    }

    /// The owner listener's port on 127.0.0.1.
    public var ownerPort: Int? { listeners.first { $0.role == .owner }?.port }

    /// Starts serving `host`. Returns the server and the owner credential, which is issued for this run only and
    /// returned only here.
    /// - Parameter v2: the R2 v2 router (plan §8.12.1), tried first for requests on the devices listener; it answers
    ///   `nil` for paths it doesn't own, which R1's router then answers as before. Without it nothing changes.
    public static func start(
        for host: LisaHost, limits: APIServerLimits = APIServerLimits(),
        v2: (@Sendable (APIRequest) async -> APIResponse?)? = nil
    ) async throws(HostError) -> (server: HostAPIServer, ownerCredential: String) {
        let devices = try deviceListener(host.settings.api, secrets: host.secrets)
        let owner = APIListenerConfiguration(role: .owner, address: "127.0.0.1", port: 0, transport: .plain)
        let router = host.router
        let server = APIServer(listeners: [devices, owner], limits: limits, logger: host.logger) { request, peer in
            if let v2, peer.listener == .devices, let answer = await v2(request) { return answer }
            guard let origin = origin(for: peer) else { return forbidden }
            return await router.handle(request, origin: origin)
        }
        let credential = host.ownerAccess.issue()
        do {
            let bound = try await server.start()
            return (HostAPIServer(server: server, ownerAccess: host.ownerAccess, listeners: bound), credential)
        } catch {
            host.ownerAccess.revoke()
            throw .apiUnavailable(error.description)
        }
    }

    /// Stops serving: requests in progress finish within the grace period, then the owner credential is revoked.
    public func stop() async {
        await server.shutdown()
        ownerAccess.revoke()
    }

    /// The device listener for the configured protection. Native TLS material is read from the secret store now and
    /// never kept as text.
    static func deviceListener(_ settings: APIServerSettings, secrets: any SecretStore) throws(HostError)
        -> APIListenerConfiguration
    {
        let transport: APIListenerTransport
        switch settings.protection {
        case .none:
            transport = .plain
        case .reverseProxy:
            transport = .reverseProxy
        case .native(let chainReference, let keyReference):
            let chain: String
            let key: String
            do {
                chain = try secrets.secret(for: chainReference).revealed
                key = try secrets.secret(for: keyReference).revealed
            } catch {
                throw .apiUnavailable("the TLS certificate or key cannot be read: \(error)")
            }
            do {
                transport = .tls(
                    try APIServerTLS(certificateChainPEM: Array(chain.utf8), privateKeyPEM: Array(key.utf8)))
            } catch {
                throw .apiUnavailable(error.description)
            }
        }
        return APIListenerConfiguration(
            role: .devices, address: settings.bindAddress, port: settings.port, transport: transport)
    }

    /// The router's view of a caller. The owner listener accepts only local peers; everything else must
    /// authenticate as a device.
    static func origin(for peer: APIPeer) -> RequestOrigin? {
        switch peer.listener {
        case .owner: peer.isLocal ? .loopbackOwner : nil
        case .devices: .authenticateHeaders(isLoopback: peer.isLocal)
        }
    }

    static let forbidden: APIResponse = {
        let body = APIErrorBody(
            code: .forbidden, message: "the owner listener accepts connections from this machine only")
        return APIResponse(
            status: 403,
            headers: ["Content-Type": "application/json", APIVersioning.versionHeader: APIVersioning.version],
            body: (try? APIJSON.encoder().encode(body)) ?? Data())
    }()
}
