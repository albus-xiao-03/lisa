// Who is calling and how the router is configured: trusted in-process callers, credentials, runtime status and the
// model configuration that health reports.

import Foundation
import LisaAPIContract
import LisaDomain
import LisaLegacyRequests

/// How a request reached the router.
public enum RequestOrigin: Hashable, Sendable {
    /// The host's own process (the Mac app's embedded mode, the CLI and the demo) acting as the local owner.
    case trustedLocalOwner
    /// A paired device or a device that is pairing; it must present a device credential. The owner credential is
    /// refused here, whatever the peer's address.
    case authenticateHeaders(isLoopback: Bool)
    /// A peer on this machine connected to the host's loopback owner listener, such as the CLI in client mode. Only
    /// the owner credential is accepted.
    case loopbackOwner
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
    /// Verifies the owner credential presented on the loopback owner listener (`RequestOrigin.loopbackOwner`), which
    /// the CLI uses in client mode; `nil` refuses every such request.
    public var ownerCredentialVerifier: (@Sendable (String) -> Bool)?
    /// Whether the host delivers local notifications itself (the Mac app), reported in health.
    public var localNotificationsLive: Bool
    /// The model configuration reported in health; `nil` reports none. It never holds an endpoint address, a key
    /// reference or a credential.
    public var model: ModelStatusDTO?
    /// R2's converter of v1 mutations (plan §8.12.2): with it, a converted route's request becomes a legacy parent and
    /// its Core-signed children instead of R1's own write and request record. `nil` keeps R1's handlers everywhere.
    public var legacyConverter: LegacyConverter?

    public init(
        applicationVersion: String, schemaVersion: Int, idempotencyRetentionDays: Int = 30,
        requestsPerMinute: Int = 300,
        ownerCredentialVerifier: (@Sendable (String) -> Bool)? = nil, localNotificationsLive: Bool = false,
        model: ModelStatusDTO? = nil, legacyConverter: LegacyConverter? = nil
    ) {
        self.applicationVersion = applicationVersion
        self.schemaVersion = schemaVersion
        self.idempotencyRetentionDays = idempotencyRetentionDays
        self.requestsPerMinute = requestsPerMinute
        self.ownerCredentialVerifier = ownerCredentialVerifier
        self.localNotificationsLive = localNotificationsLive
        self.model = model
        self.legacyConverter = legacyConverter
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
