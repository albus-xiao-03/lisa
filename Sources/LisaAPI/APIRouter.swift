// The transport-independent API router (API-01–API-03): authentication, request identities, revision checks,
// throttling and typed errors over the application facade.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaCrypto
import LisaDomain
import LisaLogging
import Synchronization

/// Routes API requests to the application. Every client (the in-process transport, the network server) goes through
/// this one router, so validation, idempotency and authorization are identical for all of them.
public final class APIRouter: Sendable {
    let application: LisaApplication
    let configuration: RouterConfiguration
    let status: any RuntimeStatusProvider
    let logger: Logger
    let limiter: RateLimiter
    private let inFlight = Mutex<Set<String>>([])

    public init(
        application: LisaApplication, configuration: RouterConfiguration, status: any RuntimeStatusProvider,
        logger: Logger
    ) {
        self.application = application
        self.configuration = configuration
        self.status = status
        self.logger = logger
        self.limiter = RateLimiter(perMinute: max(10, configuration.requestsPerMinute))
    }

    /// Handles one request. Failures become typed error responses; nothing private is echoed.
    public func handle(_ request: APIRequest, origin: RequestOrigin) async -> APIResponse {
        var routeName = "unknown"
        var callerKind = "anonymous"
        let response: APIResponse
        do {
            guard let route = APIRoute.match(method: request.method, path: request.path) else {
                throw APIFailure(
                    body: APIErrorBody(
                        code: .notFound, message: "no route matches \(request.method.rawValue) \(request.path)"))
            }
            routeName = Self.name(of: route)
            if let body = request.body, body.count > APIVersioning.maxRequestBytes {
                throw APIFailure(
                    body: APIErrorBody(
                        code: .payloadTooLarge,
                        message: "the request body exceeds \(APIVersioning.maxRequestBytes) bytes"))
            }
            let caller = try authenticate(request, route: route, origin: origin)
            callerKind = caller.scope.split(separator: ":").first.map(String.init) ?? caller.scope
            if let retryAfter = limiter.admit(caller.scope, now: application.services.clock.now()) {
                throw APIFailure(
                    body: APIErrorBody(code: .throttled, message: "too many requests", retryAfterSeconds: retryAfter))
            }
            if route.isMutation, Self.usesLedger(route) {
                response = try await idempotent(request, route: route, caller: caller)
            } else {
                response = try await dispatch(route, request: request, caller: caller, requestID: nil)
            }
        } catch {
            response = Self.error(ErrorMapping.body(for: error))
            if case .internalError = ErrorMapping.body(for: error).code {
                logger.error(
                    "request failed", ["route": .public(routeName), "error": .private(String(describing: error))])
            }
        }
        logger.info(
            "api request",
            ["route": .public(routeName), "status": .count(response.status), "caller": .public(callerKind)])
        return response
    }

    /// Pairing responses carry a credential or a pairing code; they are never stored for replay.
    static func usesLedger(_ route: APIRoute) -> Bool {
        route != .pairDevice && route != .createPairingCode
    }

    func authenticate(_ request: APIRequest, route: APIRoute, origin: RequestOrigin) throws -> Caller {
        switch origin {
        case .trustedLocalOwner:
            return Caller(principal: .localOwner, deviceID: nil)
        case .authenticateHeaders:
            if route == .pairDevice { return Caller(principal: nil, deviceID: nil) }
            guard let header = request.header(APIVersioning.authorizationHeader), header.hasPrefix("Bearer ") else {
                throw APIFailure.unauthenticated
            }
            let credential = header.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespaces)
            guard !credential.isEmpty, credential.count <= 512 else { throw APIFailure.unauthenticated }
            if let verifier = configuration.ownerCredentialVerifier, verifier(credential) {
                return Caller(principal: .localOwner, deviceID: nil)
            }
            guard let device = try application.authenticateDevice(credential: credential) else {
                throw APIFailure.unauthenticated
            }
            return Caller(principal: .pairedDevice(device.id), deviceID: device.id)
        }
    }

    /// Runs a mutation at most once per (caller, request ID). A retry returns the recorded response.
    func idempotent(_ request: APIRequest, route: APIRoute, caller: Caller) async throws -> APIResponse {
        guard let requestID = request.header(APIVersioning.requestIDHeader), Self.isValidRequestID(requestID) else {
            throw APIFailure.invalid(
                "mutating requests need a \(APIVersioning.requestIDHeader) header of 8 to 128 letters, digits or . _ : -",
                field: APIVersioning.requestIDHeader)
        }
        let scopedKey = "\(caller.scope):\(requestID)"
        let fingerprint = Self.fingerprint(request)
        switch try application.lookupRequest(scopedKey: scopedKey, fingerprint: fingerprint) {
        case .replay(let statusCode, let body):
            var replayed = APIResponse(
                status: statusCode, headers: Self.headers(contentType: "application/json"), body: body)
            replayed.headers["Lisa-Replayed"] = "true"
            return replayed
        case .mismatch:
            throw APIFailure(
                body: APIErrorBody(
                    code: .requestIDReused, message: "this request ID was already used for a different request"))
        case .unknown:
            break
        }
        let claimed = inFlight.withLock { $0.insert(scopedKey).inserted }
        guard claimed else {
            throw APIFailure(
                body: APIErrorBody(
                    code: .unavailable, message: "the same request is still being processed", retryAfterSeconds: 1))
        }
        defer { _ = inFlight.withLock { $0.remove(scopedKey) } }
        let response: APIResponse
        do {
            response = try await dispatch(route, request: request, caller: caller, requestID: requestID)
        } catch {
            response = Self.error(ErrorMapping.body(for: error))
        }
        if Self.isRecordable(response.status) {
            try application.recordRequest(
                scopedKey: scopedKey, fingerprint: fingerprint, statusCode: response.status, body: response.body,
                retentionDays: configuration.idempotencyRetentionDays)
        }
        return response
    }

    /// Definite answers are replayed; authentication, throttling and temporary failures are not.
    static func isRecordable(_ status: Int) -> Bool {
        (200..<300).contains(status) || [400, 403, 404, 409, 413].contains(status)
    }

    static func isValidRequestID(_ text: String) -> Bool {
        (8...128).contains(text.count)
            && text.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) && $0.isASCII || "._:-".unicodeScalars.contains($0)
            }
    }

    static func fingerprint(_ request: APIRequest) -> String {
        var data = Data("\(request.method.rawValue) \(request.path)\n".utf8)
        for (key, value) in request.query.sorted(by: { $0.key < $1.key }) {
            data.append(Data("\(key)=\(value)\n".utf8))
        }
        if let body = request.body { data.append(body) }
        return Digests.sha256Hex(data)
    }

    static func name(of route: APIRoute) -> String {
        String(describing: route).split(separator: "(").first.map(String.init) ?? "route"
    }
}
