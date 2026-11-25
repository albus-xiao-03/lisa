// The v2 router (plan §8.12.1, §8.6.5, §8.1.2): the sync routes of the direct HTTPS path over the Core ledger, and the
// trust routes over Core's trust state. Enrollment (`POST /v2/enrollments`) and the token-free anchors bundle
// (`GET /v2/trust/tls-anchors`) need no credential: the token, and Core's signature, authenticate them. Every other
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
                            head: status.lastPosition)))
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
                return Self.success(try EnrollmentWire.rosterBody(try trust.currentRoster()))
            default:
                return Self.failure(404, "not_found", "no such v2 route")
            }
        } catch let error as OperationEnvelopeError {
            return Self.failure(400, "invalid_request", "the body isn't a valid v2 message: \(error)")
        } catch {
            return Self.failure(503, "unavailable", "Core couldn't complete the request")
        }
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
