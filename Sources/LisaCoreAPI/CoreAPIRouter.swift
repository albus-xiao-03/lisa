// The v2 router (plan §8.12.1, §8.6.5, §8.1.2, §8.1.4, §8.1.5): the sync routes of the direct HTTPS path over the Core
// ledger, and the trust routes over Core's trust state. Enrollment (`POST /v2/enrollments`), the token-free anchors
// bundle (`GET /v2/trust/tls-anchors`), credential reset (`POST /v2/devices/current/credential-reset`) and challenge
// issue (`POST /v2/challenges`) need no credential: the token or the device's key, and Core's signature, authenticate
// them, and a device whose credential a restore rewound can still use them. Every other
// request is an enrolled device's, by its bearer credential, and the roster gives each device's operation key. Paths
// outside `/v2/` get nil, so R1's router answers them as before. Bodies are canonical JSON (`SyncWire`,
// `EnrollmentWire`).

import Foundation
import LisaAPIContract
import LisaCoreLedger
import LisaCrypto
import LisaSyncProtocol

/// Answers the v2 sync routes.
public final class CoreAPIRouter: Sendable {
    public static let versionHeader = "Lisa-API-Version"
    /// The capabilities a client requires, comma-separated; any Core lacks gets `upgrade_required` (§8.12.1).
    public static let requiredFeaturesHeader = "Lisa-Required-Features"
    /// The server's larger body limits for v2 paths (plan §8.12.1): `POST /v2/operations` takes up to 512 KiB of signed
    /// bytes. The composition root passes them as `APIServerLimits.bodyLimitsByPath`; every other path keeps R1's limit.
    public static let bodyLimits = ["/v2/operations": SyncWire.maximumBodyBytes]
    /// What this Core offers, strictly ascending.
    public static let features = [
        "challenges", "changes", "credential-reset", "enrollment", "operations", "receipts", "trust",
    ]

    let ledger: CoreLedger
    let trust: CoreTrust?
    let authenticate: @Sendable (String) -> Bool
    let roster: @Sendable (Identifier128) -> P256Verifier?

    /// The sync routes alone, with devices authenticated and their keys given by the caller.
    /// - Parameters:
    ///   - authenticate: whether a bearer credential belongs to an active paired device.
    ///   - roster: each enrolled device's operation key.
    public init(
        ledger: CoreLedger, authenticate: @escaping @Sendable (String) -> Bool,
        roster: @escaping @Sendable (Identifier128) -> P256Verifier?
    ) {
        self.ledger = ledger
        self.trust = nil
        self.authenticate = authenticate
        self.roster = roster
    }

    /// The sync and trust routes, with devices authenticated by Core's registry and their keys from it: a revoked
    /// device's credential and operations are refused.
    public init(trust: CoreTrust) {
        self.ledger = trust.ledger
        self.trust = trust
        self.authenticate = { trust.authenticate(credential: $0) != nil }
        self.roster = { trust.operationKey(of: $0) }
    }

    /// The answer to a `/v2/` request; `nil` for any other path.
    public func handle(_ request: APIRequest) -> APIResponse? {
        guard request.path == "/v2" || request.path.hasPrefix("/v2/") else { return nil }
        if let refusal = Self.negotiate(request) { return refusal }
        if let trust, let answer = Self.credentialFree(request, trust: trust) { return answer }
        guard let credential = Self.bearer(request), authenticate(credential) else {
            return Self.failure(401, "unauthenticated", "a valid device credential is required")
        }
        do {
            switch (request.method, request.path) {
            case (.get, "/v2/capabilities"):
                let status = try ledger.status()
                return Self.success(
                    try SyncWire.capabilitiesBody(
                        SyncWire.Capabilities(
                            apiVersion: SyncWire.apiVersion, datasetID: status.datasetID, epochID: status.epochID,
                            head: status.lastPosition, features: Self.features)))
            case (.post, "/v2/operations"):
                let operations = try SyncWire.operations(fromSubmission: [UInt8](request.body ?? Data()))
                let outcomes = try ledger.intake(operations, deviceKey: roster).map(Self.wire)
                return Self.success(try SyncWire.outcomesBody(outcomes))
            case (.post, "/v2/receipts/lookup"):
                let ids = try SyncWire.lookupIDs(fromBody: [UInt8](request.body ?? Data()))
                var receipts: [(operationID: Identifier128, receipt: SignedCoreReceipt?)] = []
                for id in ids { receipts.append((id, try ledger.receipt(for: id))) }
                return Self.success(try SyncWire.receiptsBody(receipts))
            case (.get, "/v2/changes"):
                guard let partition = request.query["partition"], !partition.isEmpty,
                    let after = request.query["after"].flatMap({ Int64($0) }), after >= 0
                else { return Self.failure(400, "invalid_request", "partition and after are required") }
                let limit = request.query["limit"].flatMap { Int($0) }.map { min(max($0, 1), 512) } ?? 256
                return Self.success(
                    try SyncWire.pageBody(try ledger.changePage(partition: partition, after: after, maxEntries: limit)))
            case (.get, "/v2/trust"):
                guard let trust else { return Self.failure(404, "not_found", "no such v2 route") }
                return Self.success(
                    try EnrollmentWire.trustBody(try trust.currentRoster(), transitions: try ledger.keyTransitions()))
            default:
                return Self.failure(404, "not_found", "no such v2 route")
            }
        } catch let error as OperationEnvelopeError {
            return Self.failure(400, "invalid_request", "the body isn't a valid v2 message: \(error)")
        } catch {
            return Self.failure(503, "unavailable", "Core couldn't complete the request")
        }
    }

    /// `upgrade_required` (426) for a request that names another major API version or requires a feature Core lacks;
    /// nil otherwise. A request without a version header is taken as 2.x.
    static func negotiate(_ request: APIRequest) -> APIResponse? {
        if let version = header(request, versionHeader),
            SyncWire.majorVersion(of: version) != SyncWire.majorVersion(of: SyncWire.apiVersion)
        {
            return failure(426, "upgrade_required", "Core speaks API \(SyncWire.apiVersion)")
        }
        if let required = header(request, requiredFeaturesHeader) {
            let names = required.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard names.allSatisfy({ $0.isEmpty || features.contains($0) }) else {
                return failure(426, "upgrade_required", "Core lacks a capability this client requires")
            }
        }
        return nil
    }

    /// A header's value, whatever the case of its name.
    static func header(_ request: APIRequest, _ name: String) -> String? {
        request.headers[name] ?? request.headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    /// The routes that need no credential; nil for any other.
    static func credentialFree(_ request: APIRequest, trust: CoreTrust) -> APIResponse? {
        switch (request.method, request.path) {
        case (.post, "/v2/enrollments"):
            do {
                switch try trust.enroll([UInt8](request.body ?? Data())) {
                case .enrolled(let body), .duplicate(let body):
                    return success(body)
                case .refused(let refusal):
                    var message = "Core refused the enrollment request"
                    if case .responsePurged(let device) = refusal {
                        message =
                            "this pairing finished earlier for device \(device.hex); pair again if it isn't connected"
                    }
                    return failure(refusal.status, refusal.code, message)
                }
            } catch {
                return failure(503, "unavailable", "Core couldn't complete the request")
            }
        case (.post, "/v2/devices/current/credential-reset"):
            do {
                switch try trust.resetCredential([UInt8](request.body ?? Data())) {
                case .reset(let device, let time):
                    return success(try CredentialResetRequest.answerBody(deviceID: device, resetAt: time))
                case .refused(let refusal):
                    return failure(refusal.status, refusal.code, "Core refused the credential reset")
                }
            } catch {
                return failure(503, "unavailable", "Core couldn't complete the request")
            }
        case (.post, "/v2/challenges"):
            guard let asked = try? Challenge.request(fromBody: [UInt8](request.body ?? Data())) else {
                return failure(400, "invalid_request", "deviceID and purpose are required")
            }
            guard let challenge = try? trust.issueChallenge(device: asked.deviceID, purpose: asked.purpose),
                let body = try? challenge.canonicalBody()
            else { return failure(503, "unavailable", "Core couldn't complete the request") }
            return success(body)
        case (.get, "/v2/trust/tls-anchors"):
            guard let anchors = trust.anchors else {
                return failure(404, "not_found", "Core has no anchors bundle in pin mode")
            }
            guard let body = try? EnrollmentWire.anchorsBody(anchors) else {
                return failure(503, "unavailable", "Core couldn't complete the request")
            }
            return success(body)
        default:
            return nil
        }
    }

    static func wire(_ outcome: CoreIntakeOutcome) -> SyncWire.Outcome {
        switch outcome {
        case .receipted(let receipt): .receipted(receipt)
        case .duplicate(let receipt): .duplicate(receipt)
        case .rejectedIdentityReuse: .identityReuse
        case .rejectedSequenceReuse: .sequenceReuse
        case .unverified(let error): .unverified(String(describing: error))
        }
    }

    static func bearer(_ request: APIRequest) -> String? {
        let value = request.headers["authorization"] ?? request.headers["Authorization"]
        guard let value, value.hasPrefix("Bearer ") else { return nil }
        let credential = String(value.dropFirst("Bearer ".count))
        return (1...512).contains(credential.count) ? credential : nil
    }

    static func success(_ body: [UInt8]) -> APIResponse {
        APIResponse(
            status: 200, headers: ["Content-Type": "application/json", versionHeader: SyncWire.apiVersion],
            body: Data(body))
    }

    static func failure(_ status: Int, _ code: String, _ message: String) -> APIResponse {
        let object = try? CanonicalObject([("code", .string(code)), ("message", .string(message))])
        let body = object.flatMap {
            try? CanonicalEncoder.encode(.object($0), limits: CanonicalLimits(maxBytes: 4_096))
        }
        return APIResponse(
            status: status, headers: ["Content-Type": "application/json", versionHeader: SyncWire.apiVersion],
            body: Data(body ?? []))
    }
}
