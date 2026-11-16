// Who is calling and how the router is configured: trusted in-process callers, credentials and runtime status.

import Foundation
import LisaDomain

/// How a request reached the router.
public enum RequestOrigin: Hashable, Sendable {
    /// The host's own process (the Mac app's embedded mode, the CLI and the demo) acting as the local owner.
    case trustedLocalOwner
    /// Any other caller; it must present a device credential or the owner credential.
    case authenticateHeaders(isLoopback: Bool)
}

/// The runtime facts health reports. Supplied by the runtime; the router never reads them itself.
public struct RuntimeStatus: Hashable, Sendable {
    public var startedAt: Date
    public var lastCycleAt: Date?
    public var lastCycleProblem: String?
    public var warnings: [String]

    public init(startedAt: Date, lastCycleAt: Date? = nil, lastCycleProblem: String? = nil, warnings: [String] = []) {
        self.startedAt = startedAt
        self.lastCycleAt = lastCycleAt
        self.lastCycleProblem = lastCycleProblem
        self.warnings = warnings
    }
}

/// Supplies runtime status for `GET /v1/health`.
public protocol RuntimeStatusProvider: Sendable {
    func runtimeStatus() -> RuntimeStatus
}

/// Router settings from the validated configuration.
public struct RouterConfiguration: Sendable {
    public var applicationVersion: String
    public var schemaVersion: Int
    /// How long request IDs are remembered (API-03); at least the clients' maximum offline retry period.
    public var idempotencyRetentionDays: Int
    /// Requests per principal per minute before throttling.
    public var requestsPerMinute: Int
    /// Verifies the local owner's credential for loopback clients such as the CLI in client mode; `nil` disables it.
    public var ownerCredentialVerifier: (@Sendable (String) -> Bool)?
    /// Whether the host delivers local notifications itself (the Mac app), reported in health.
    public var localNotificationsLive: Bool

    public init(
        applicationVersion: String, schemaVersion: Int, idempotencyRetentionDays: Int = 30,
        requestsPerMinute: Int = 300,
        ownerCredentialVerifier: (@Sendable (String) -> Bool)? = nil, localNotificationsLive: Bool = false
    ) {
        self.applicationVersion = applicationVersion
        self.schemaVersion = schemaVersion
        self.idempotencyRetentionDays = idempotencyRetentionDays
        self.requestsPerMinute = requestsPerMinute
        self.ownerCredentialVerifier = ownerCredentialVerifier
        self.localNotificationsLive = localNotificationsLive
    }
}

/// The authenticated caller of one request.
struct Caller: Sendable {
    var principal: Principal?
    /// The device making the request, for `/v1/devices/current/...` routes.
    var deviceID: DeviceID?

    /// Scopes request IDs per caller so two devices can never collide.
    var scope: String {
        switch principal {
        case .localOwner: "owner"
        case .pairedDevice(let id): "device:\(id.rawValue)"
        case .demonstration: "demonstration"
        case .runtime, .model, nil: "anonymous"
        }
    }
}
