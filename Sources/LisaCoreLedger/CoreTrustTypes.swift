// Core's trust configuration and the typed answers of enrollment (plan §8.1.2–§8.1.4).

import LisaCrypto
import LisaSyncProtocol
import LisaTrust

/// Core's TLS identity as pairing texts and rosters describe it: the trust mode, the intended host, the pin of the
/// leaf Core serves now, the authorized pins (current, and next during an overlap) and, in `ca` mode, the owner CA and
/// the intermediates Core is configured with (DER).
public struct CoreTLSIdentity: Hashable, Sendable {
    public let mode: CoreTLSMode
    /// `https://<host>[:port]`, as pairing texts carry it.
    public let coreURL: String
    /// SHA-256 of the SubjectPublicKeyInfo of the leaf Core serves now: the pin a pairing text carries.
    public let servedPin: Digest256
    /// The pins the roster authorizes, current first.
    public let pins: [TLSPin]
    public let caCertificate: [UInt8]?
    public let intermediates: [[UInt8]]

    public init(
        mode: CoreTLSMode, coreURL: String, servedPin: Digest256, pins: [TLSPin], caCertificate: [UInt8]? = nil,
        intermediates: [[UInt8]] = []
    ) throws(CoreLedgerError) {
        guard (mode == .ca) == (caCertificate != nil) else { throw .encodingFailed("the TLS identity's CA") }
        guard (1...2).contains(pins.count), pins.contains(where: { $0.spkiDigest == servedPin }) else {
            throw .encodingFailed("the TLS identity's pins")
        }
        guard mode == .ca || intermediates.isEmpty else { throw .encodingFailed("the TLS identity's intermediates") }
        self.mode = mode
        self.coreURL = coreURL
        self.servedPin = servedPin
        self.pins = pins
        self.caCertificate = caCertificate
        self.intermediates = intermediates
    }
}

/// Enrollment and trust limits (plan §8.1.2, §8.15.1).
public struct CoreTrustConfiguration: Hashable, Sendable {
    /// How long an enrollment stays open, in milliseconds (10 minutes).
    public var enrollmentLifetime: Int64 = 600_000
    /// How long Core keeps a consumed enrollment's public-only response, in milliseconds (7 days).
    public var responseRetention: Int64 = 7 * 86_400_000
    /// The most active devices.
    public var maximumDevices = 10
    /// The failed attempt that invalidates an open enrollment.
    public var maximumAttempts: Int64 = 5
    /// How old the newest roster may grow before Core signs a renewal, in milliseconds (1 day).
    public var rosterRenewalInterval: Int64 = 86_400_000
    public var policyVersion: Int64 = 1
    public var maximumNearbyTrustAgeDays: Int64 = TrustRoster.defaultNearbyTrustAgeDays
    /// The capabilities a newly enrolled device gets.
    public var deviceCapabilities: [String] = ["sync"]
    /// How long a credential-reset token stays usable, in milliseconds (10 minutes, §8.1.4).
    public var resetLifetime: Int64 = 600_000

    public init() {}
}

/// Why Core refused an enrollment request: the typed `enrollment_*` codes (plan §8.12.1).
public enum CoreEnrollmentRefusal: Hashable, Sendable {
    /// The body isn't a well-formed request; nothing was counted.
    case malformed
    case unknown
    /// Consumed by a request with another digest; a security event is recorded.
    case consumed
    case expired
    case invalidated
    /// Consumed by this exact request, but the stored response has been purged after 7 days. Names the device.
    case responsePurged(deviceID: Identifier128)
    /// The token, signature, keys or fields didn't verify; the attempt was counted.
    case rejected
    /// The dataset already has its maximum of active devices; the attempt was counted.
    case deviceLimit

    /// The v2 error code.
    public var code: String {
        switch self {
        case .malformed: "invalid_request"
        case .unknown: "enrollment_unknown"
        case .consumed: "enrollment_consumed"
        case .expired: "enrollment_expired"
        case .invalidated: "enrollment_invalidated"
        case .responsePurged: "enrollment_response_purged"
        case .rejected: "enrollment_rejected"
        case .deviceLimit: "enrollment_device_limit"
        }
    }

    /// The HTTP status.
    public var status: Int {
        switch self {
        case .malformed: 400
        case .unknown: 404
        case .consumed, .responsePurged, .deviceLimit: 409
        case .expired, .invalidated: 410
        case .rejected: 403
        }
    }
}

/// What Core answered an enrollment request.
public enum CoreEnrollmentAnswer: Hashable, Sendable {
    /// The enrollment was consumed by this request: the response's exact bytes.
    case enrolled([UInt8])
    /// The same request again: the stored response's exact bytes, whatever the expiry.
    case duplicate([UInt8])
    case refused(CoreEnrollmentRefusal)
}

/// An enrollment as the owner's list shows it.
public struct CoreEnrollmentRecord: Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case open
        case consumed
        case invalidated
        case cancelled
    }

    public let enrollmentID: Identifier128
    public let state: State
    public let deviceName: String
    public let deviceClass: RosterDevice.DeviceClass
    public let issuedAt: Int64
    public let expiresAt: Int64
    public let attempts: Int64
    public let deviceID: Identifier128?
    /// Whether the stored response is still kept (consumed enrollments only).
    public let responseKept: Bool
}

/// A device in Core's registry.
public struct CoreDeviceRecord: Hashable, Sendable {
    public let deviceID: Identifier128
    public let name: String
    public let deviceClass: RosterDevice.DeviceClass
    public let status: RosterDevice.Status
    public let enrolledAt: Int64
    /// When the device first authenticated after enrolling; none for "enrolled, never seen".
    public let firstSeenAt: Int64?
}

/// A trust event: a refused enrollment that deserves the owner's attention, a revocation, an invalidation.
public struct CoreTrustEvent: Hashable, Sendable {
    public let kind: String
    public let subject: Identifier128?
    public let detail: String
    public let recordedAt: Int64
}
