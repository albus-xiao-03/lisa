// The typed v1 API client: request construction, credentials, the version check, error mapping and 401 handling.

import Foundation
import LisaAPIContract

/// A typed client for the Lisa v1 API over any `APITransport` (API-02, API-03).
///
/// - Mutating requests always carry a `Lisa-Request-ID`: the caller's, or a new random lowercase UUID. Retrying a
///   mutation with the same ID never repeats it on the host.
/// - While a device credential is stored, requests carry `Authorization: Bearer <credential>`, except pairing, which
///   the one-time pairing code authenticates.
/// - A response whose `Lisa-API-Version` major version is not 1 is rejected with `ClientError.incompatibleVersion`.
/// - A 401 response clears the stored pairing and keeps the installation identifier: the host removed this device
///   (plan §6.3) and it must pair again.
public actor LisaAPIClient {
    /// How a request is authenticated.
    enum Authentication: Sendable {
        /// The stored device credential; without one the request fails when the client requires pairing.
        case deviceCredential
        /// The stored device credential when there is one; it is never required.
        case optionalDeviceCredential
        /// No credential: the request carries its own proof, such as a pairing code.
        case none
    }

    private static let contentTypeHeader = "Content-Type"
    private static let jsonContentType = "application/json"

    private let transport: any APITransport
    private let credentials: any CredentialStore
    private let requiresPairing: Bool

    /// - Parameters:
    ///   - transport: carries requests to the host, such as the host's in-process transport.
    ///   - credentials: holds this installation's identity and device credential.
    ///   - requiresPairing: when `true`, as for a remote device, every route except health and pairing fails with
    ///     `ClientError.notPaired` before anything is sent while no credential is stored. Pass `false` only for a
    ///     transport that authenticates the caller itself, such as the local owner's in-process transport.
    public init(transport: any APITransport, credentials: any CredentialStore, requiresPairing: Bool = true) {
        self.transport = transport
        self.credentials = credentials
        self.requiresPairing = requiresPairing
    }

    /// This installation's identity, without its credential. The first call creates and stores an identity with a
    /// random installation identifier, which stays the same until the identity is cleared.
    public func installation() throws(ClientError) -> ClientInstallation {
        if let stored = try storedIdentity() { return ClientInstallation(stored) }
        let created = ClientIdentity.newInstallation()
        try storeIdentity(created)
        return ClientInstallation(created)
    }

    // MARK: - Sending

    /// Sends a request to `route` and returns its success response.
    func send(
        _ route: APIRoute, query: [String: String] = [:], body: Data? = nil, requestID: String? = nil
    ) async throws(ClientError) -> APIResponse {
        try await send(
            method: route.method, path: route.path, query: query, body: body, requestID: requestID,
            authentication: Self.authentication(for: route))
    }

    /// Sends a request to `route` and decodes its JSON success body.
    func call<Response: Decodable>(
        _ route: APIRoute, query: [String: String] = [:], body: Data? = nil, requestID: String? = nil,
        returning type: Response.Type
    ) async throws(ClientError) -> Response {
        let response = try await send(route, query: query, body: body, requestID: requestID)
        return try ResponseInterpreter.decode(type, from: response)
    }

    /// Sends a request and returns its success response. A mutating request carries `requestID`, or a random one.
    func send(
        method: HTTPMethod, path: String, query: [String: String], body: Data?, requestID: String?,
        authentication: Authentication
    ) async throws(ClientError) -> APIResponse {
        var headers: [String: String] = [:]
        if method != .get {
            let id = requestID ?? RequestID.random()
            guard RequestID.isValid(id) else { throw .invalidRequestID(id) }
            headers[APIVersioning.requestIDHeader] = id
        }
        let credential = try credential(for: authentication)
        if let credential { headers[APIVersioning.authorizationHeader] = "Bearer \(credential)" }
        if let body {
            guard body.count <= APIVersioning.maxRequestBytes else {
                throw .invalidArgument(name: "body", reason: "larger than \(APIVersioning.maxRequestBytes) bytes")
            }
            headers[Self.contentTypeHeader] = Self.jsonContentType
        }
        let request = APIRequest(method: method, path: path, query: query, headers: headers, body: body)
        let response: APIResponse
        do {
            response = try await transport.send(request)
        } catch let error as APITransportError {
            throw .transport(error)
        } catch {
            if error is CancellationError || Task.isCancelled { throw .cancelled }
            throw .transport(.interrupted("the transport failed with \(type(of: error))"))
        }
        try ResponseInterpreter.checkVersion(of: response)
        guard response.isSuccess else {
            if response.status == 401 { clearPairing(ifCredentialIs: credential) }
            throw ResponseInterpreter.failure(for: response)
        }
        return response
    }

    /// Encodes a request body with `APIJSON.encoder()`.
    func encode<Body: Encodable>(_ body: Body) throws(ClientError) -> Data {
        do {
            return try APIJSON.encoder().encode(body)
        } catch {
            throw .encoding("\(Body.self) could not be encoded as JSON")
        }
    }

    // MARK: - Identity

    /// The stored identity, or `nil`.
    func storedIdentity() throws(ClientError) -> ClientIdentity? {
        do {
            return try credentials.load()
        } catch {
            throw .credentialStore(String(describing: error))
        }
    }

    /// Replaces the stored identity.
    func storeIdentity(_ identity: ClientIdentity) throws(ClientError) {
        do {
            try credentials.save(identity)
        } catch {
            throw .credentialStore(String(describing: error))
        }
    }

    /// The credential a request carries.
    private func credential(for authentication: Authentication) throws(ClientError) -> String? {
        guard authentication != .none else { return nil }
        let credential = try storedIdentity()?.credential
        if credential == nil, authentication == .deviceCredential, requiresPairing { throw .notPaired }
        return credential
    }

    /// Drops the stored pairing after a 401, unless a different credential was stored meanwhile, for example by
    /// pairing again while the rejected request was in flight. This is best effort: when the store fails, the next
    /// rejected request tries again.
    private func clearPairing(ifCredentialIs sent: String?) {
        guard let sent, let identity = try? credentials.load(), identity.credential == sent else { return }
        try? credentials.save(identity.unpaired())
    }

    private static func authentication(for route: APIRoute) -> Authentication {
        switch route {
        case .pairDevice: .none
        case .health: .optionalDeviceCredential
        default: .deviceCredential
        }
    }
}
