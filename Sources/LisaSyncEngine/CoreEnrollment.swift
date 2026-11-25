// Enrollment on the device (plan §8.1.2 steps 3–6 and "After a failure or retry"). The owner text is validated before
// anything touches the network. In `ca` mode the token-free anchors bundle is fetched over a connection that accepts
// only the owner text's pinned leaf for the intended host, and checked against the owner text's CA digest and Core
// signing key; in `pin` mode there is no GET. Only then does the device prepare its request and keep it, with the
// validated key, the expected bindings and the TLS policy, in the device-only pending item, before the one
// token-bearing POST. The response counts only after every binding verifies with the owner text's key; completion is
// one durable replica transaction, and only then is the pending item removed. A lost or unverifiable result keeps the
// item: `resume()` replays the identical bytes under the saved policy until the retry deadline.

import Foundation
import LisaCrypto
import LisaReplicaStore
import LisaSyncProtocol
import LisaTrust

/// The TLS policy every connection to Core must satisfy (§8.1.2 step 3, §8.1.4): the intended host; the leaf's
/// SubjectPublicKeyInfo digest among `pins`; in `ca` mode a chain to `caCertificate` as the only anchor, helped by
/// `intermediates` from the verified bundle; in `pin` mode the pinned leaf as the only anchor.
public struct CoreTLSPolicy: Hashable, Sendable {
    public let host: String
    public let mode: CoreTLSMode
    public let pins: [Digest256]
    public let caCertificate: [UInt8]?
    public let intermediates: [[UInt8]]

    public init(host: String, mode: CoreTLSMode, pins: [Digest256], caCertificate: [UInt8]?, intermediates: [[UInt8]]) {
        self.host = host
        self.mode = mode
        self.pins = pins
        self.caCertificate = caCertificate
        self.intermediates = intermediates
    }

    /// The bootstrap connection before the anchors are known: the owner text's pin, the pinned leaf as the only
    /// anchor, the intended host.
    public static func bootstrap(host: String, pin: Digest256) -> CoreTLSPolicy {
        CoreTLSPolicy(host: host, mode: .pin, pins: [pin], caCertificate: nil, intermediates: [])
    }
}

/// What Core answered the enrollment POST.
public enum EnrollmentPostAnswer: Hashable, Sendable {
    /// 200: the response's exact bytes.
    case response([UInt8])
    /// Core's typed refusal.
    case refused(status: Int, code: String)
}

/// The two enrollment exchanges, each over a connection that enforces `policy` (including on a reconnection) and
/// never follows a redirect. Production: LisaSyncHTTP with the Apple trust evaluator; on Linux the harness's libcurl
/// pinning transport.
public protocol EnrollmentTransport: Sendable {
    /// `GET /v2/trust/tls-anchors`: carries no token.
    func fetchAnchors(coreURL: String, policy: CoreTLSPolicy) async throws -> SignedBody
    /// `POST /v2/enrollments` with the exact signed request.
    func postEnrollment(_ request: SignedBody, coreURL: String, policy: CoreTLSPolicy) async throws
        -> EnrollmentPostAnswer
}

/// The device-only pending item (§8.1.2 step 4): a Keychain item on Apple platforms. Its bytes are secret-bearing and
/// never reach the replica, a log, a diagnostic or an export.
public protocol PendingEnrollmentStore: Sendable {
    func save(_ item: [UInt8]) throws
    func load() throws -> [UInt8]?
    func delete() throws
}

/// The keys a device creates for enrollment; on Apple platforms they live in the Secure Enclave or Keychain.
public struct DeviceEnrollmentKeys: Sendable {
    public let operationKey: any MessageSigning
    public let exportKey: P256AgreementPublicKey
    public let credential: CoreCredential

    public init(operationKey: any MessageSigning, exportKey: P256AgreementPublicKey, credential: CoreCredential) {
        self.operationKey = operationKey
        self.exportKey = exportKey
        self.credential = credential
    }
}

/// One attempt as the pending item keeps it: the exact signed request, the validated Core key, the bindings, the TLS
/// policy and the retry deadline. Secret-bearing: `description` shows none of it.
public struct PendingEnrollment: Hashable, Sendable, CustomStringConvertible {
    /// How long after the owner text's expiry a retry may still go out (24 hours).
    public static let retryGrace: Int64 = 86_400_000

    public let coreURL: String
    public let request: SignedBody
    public let coreSigningKey: [UInt8]
    public let policy: CoreTLSPolicy
    public let retryUntil: Int64

    public init(coreURL: String, request: SignedBody, coreSigningKey: [UInt8], policy: CoreTLSPolicy, retryUntil: Int64)
    {
        self.coreURL = coreURL
        self.request = request
        self.coreSigningKey = coreSigningKey
        self.policy = policy
        self.retryUntil = retryUntil
    }

    public var description: String { "PendingEnrollment(retry pending until \(retryUntil))" }

    /// The item's bytes, canonical JSON.
    public func encoded() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            var policyFields: [(String, CanonicalValue)] = [
                ("host", .string(policy.host)), ("mode", .string(policy.mode.rawValue)),
                ("pins", .array(policy.pins.map { .string($0.hex) })),
                ("intermediates", .array(policy.intermediates.map { .string(StrictBase64URL.encode($0)) })),
            ]
            if let ca = policy.caCertificate {
                policyFields.append(("caCertificate", .string(StrictBase64URL.encode(ca))))
            }
            let object = try CanonicalObject([
                ("coreURL", .string(coreURL)), ("request", request.canonicalValue()),
                ("coreSigningKey", .string(StrictBase64URL.encode(coreSigningKey))),
                ("policy", .object(try CanonicalObject(policyFields))), ("retryUntil", .integer(retryUntil)),
            ])
            return try CanonicalEncoder.encode(.object(object), limits: CanonicalLimits(maxBytes: 262_144))
        } catch {
            throw .invalidField("pending")
        }
    }

    public static func decode(_ bytes: [UInt8]) throws(OperationEnvelopeError) -> PendingEnrollment {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(bytes, limits: CanonicalLimits(maxBytes: 262_144)))
            var policy = CanonicalFieldReader(object: try reader.object("policy"))
            guard let mode = CoreTLSMode(rawValue: try policy.string("mode")) else {
                throw OperationEnvelopeError.invalidField("pending.mode")
            }
            let pins = try policy.array("pins").map { value in
                guard case .string(let hex) = value, let pin = try? Digest256(hex: hex) else {
                    throw OperationEnvelopeError.invalidField("pending.pins")
                }
                return pin
            }
            let intermediates = try policy.array("intermediates").map { value in
                guard case .string(let text) = value, let der = try? StrictBase64URL.decode(text) else {
                    throw OperationEnvelopeError.invalidField("pending.intermediates")
                }
                return der
            }
            let ca = try policy.optionalString("caCertificate").map { text in
                guard let der = try? StrictBase64URL.decode(text) else {
                    throw OperationEnvelopeError.invalidField("pending.caCertificate")
                }
                return der
            }
            let host = try policy.string("host")
            try policy.finish()
            let item = PendingEnrollment(
                coreURL: try reader.string("coreURL"),
                request: try SignedBody.decode(
                    try reader.value("request"), maximumBytes: EnrollmentRequest.maximumBytes),
                coreSigningKey: try reader.bytes("coreSigningKey"),
                policy: CoreTLSPolicy(
                    host: host, mode: mode, pins: pins, caCertificate: ca, intermediates: intermediates),
                retryUntil: try reader.integer("retryUntil"))
            try reader.finish()
            return item
        } catch let error as OperationEnvelopeError {
            throw error
        } catch {
            throw .invalidField("pending")
        }
    }
}

/// Why an enrollment attempt stopped.
public enum CoreEnrollmentError: Error, Hashable, Sendable {
    /// The owner text failed validation: nothing was sent.
    case ownerText(TrustError)
    /// The anchors bundle failed its checks (signature, dataset or CA digest): no token was sent.
    case anchors(EnrollmentVerificationError)
    /// A connection failed or was refused under the TLS policy. Before the POST no token was sent; after it the
    /// pending item stays for a retry.
    case connection(String)
    /// Core's typed refusal (`enrollment_*`).
    case refused(status: Int, code: String)
    /// The response didn't verify: "Pairing result could not be verified". The pending item stays.
    case unverifiableResult(EnrollmentVerificationError)
    /// The pending attempt passed its retry deadline and was removed.
    case retryExpired
    case pendingItem(String)
    case replica(ReplicaStoreError)
}

/// A completed enrollment.
public struct CompletedEnrollment: Hashable, Sendable {
    public let deviceID: Identifier128
    public let roster: TrustRoster
    /// Whether this call published the completion (false when it had been published already).
    public let published: Bool
}

/// The device side of enrollment.
public struct CoreEnrollment: Sendable {
    /// Refusals after which the pending item is removed; others keep it until the retry deadline.
    public static let terminalCodes: Set<String> = [
        "enrollment_consumed", "enrollment_expired", "enrollment_invalidated",
    ]

    let replica: ReplicaStore
    let transport: any EnrollmentTransport
    let pending: any PendingEnrollmentStore
    let now: @Sendable () -> Int64

    public init(
        replica: ReplicaStore, transport: any EnrollmentTransport, pending: any PendingEnrollmentStore,
        now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
    ) {
        self.replica = replica
        self.transport = transport
        self.pending = pending
        self.now = now
    }

    /// Runs a new attempt from the owner text.
    public func enroll(
        ownerText: String, deviceName: String, deviceClass: RosterDevice.DeviceClass, keys: DeviceEnrollmentKeys
    ) async throws(CoreEnrollmentError) -> CompletedEnrollment {
        let text: PairingText
        do {
            text = try PairingText.decode(ownerText)
        } catch {
            throw .ownerText(error)
        }
        guard let host = URLComponents(string: text.coreURL)?.host else { throw .ownerText(.invalidCoreURL) }
        let coreKey = text.coreSigningKey.verifier
        // TLS preflight: in `ca` mode, the token-free anchors under the bootstrap pin; in `pin` mode, nothing.
        var policy = CoreTLSPolicy(host: host, mode: .pin, pins: [text.leafPin], caCertificate: nil, intermediates: [])
        if text.trustMode == .ca, let caDigest = text.caDigest {
            let signed: SignedBody
            do {
                signed = try await transport.fetchAnchors(
                    coreURL: text.coreURL, policy: .bootstrap(host: host, pin: text.leafPin))
            } catch {
                throw .connection(String(describing: error))
            }
            let bundle: TLSAnchorsBundle
            do {
                bundle = try EnrollmentSigning.verifyAnchors(
                    signed, dataset: text.datasetID, caDigest: caDigest, coreKey: coreKey)
            } catch {
                throw .anchors(error)
            }
            policy = CoreTLSPolicy(
                host: host, mode: .ca, pins: [text.leafPin], caCertificate: bundle.caCertificate,
                intermediates: bundle.intermediates)
        }
        // Device preparation: the request, signed by the new operation key, kept in the pending item first.
        let request: SignedBody
        do {
            request = try EnrollmentSigning.signRequest(
                EnrollmentRequest(
                    enrollmentID: text.enrollmentID, token: text.token.bytes, datasetID: text.datasetID,
                    trustMode: text.trustMode == .ca ? .ca : .pin, leafPin: text.leafPin, caDigest: text.caDigest,
                    issuerFingerprint: text.coreSigningKey.fingerprint, deviceName: deviceName,
                    deviceClass: deviceClass, operationKey: keys.operationKey.verifier.spkiDER,
                    exportKey: keys.exportKey.spkiDER, credentialVerifier: keys.credential.verifier,
                    incarnationID: replica.incarnationID, createdAt: now()),
                with: keys.operationKey)
        } catch {
            throw .pendingItem("the request could not be prepared")
        }
        let item = PendingEnrollment(
            coreURL: text.coreURL, request: request, coreSigningKey: coreKey.spkiDER, policy: policy,
            retryUntil: text.expiresAt + PendingEnrollment.retryGrace)
        do {
            try pending.save(try item.encoded())
        } catch {
            throw .pendingItem("the pending item could not be saved")
        }
        return try await post(item)
    }

    /// Resumes the pending attempt after a restart or a lost result: finishes cleanup when its completion is already
    /// published, removes it after its deadline, and otherwise replays the identical bytes under the saved policy.
    /// Returns nil when no attempt is pending.
    public func resume() async throws(CoreEnrollmentError) -> CompletedEnrollment? {
        let item: PendingEnrollment
        do {
            guard let bytes = try pending.load() else { return nil }
            item = try PendingEnrollment.decode(bytes)
        } catch {
            throw .pendingItem("the pending item could not be read")
        }
        let digest = EnrollmentSigning.requestDigest(item.request)
        do {
            if let trust = try replica.trustState(), trust.requestDigest == digest,
                let roster = try replica.newestRoster()?.roster
            {
                try? pending.delete()
                return CompletedEnrollment(deviceID: trust.deviceID, roster: roster, published: false)
            }
        } catch {
            throw .replica(error)
        }
        guard now() < item.retryUntil else {
            try? pending.delete()
            throw .retryExpired
        }
        return try await post(item)
    }

    /// The one token-bearing POST, then verification and completion.
    func post(_ item: PendingEnrollment) async throws(CoreEnrollmentError) -> CompletedEnrollment {
        let answer: EnrollmentPostAnswer
        do {
            answer = try await transport.postEnrollment(item.request, coreURL: item.coreURL, policy: item.policy)
        } catch {
            throw .connection(String(describing: error))
        }
        switch answer {
        case .refused(let status, let code):
            if Self.terminalCodes.contains(code) { try? pending.delete() }
            throw .refused(status: status, code: code)
        case .response(let bytes):
            return try complete(item, responseBytes: bytes)
        }
    }

    func complete(_ item: PendingEnrollment, responseBytes: [UInt8]) throws(CoreEnrollmentError) -> CompletedEnrollment
    {
        let digest = EnrollmentSigning.requestDigest(item.request)
        let verified: VerifiedEnrollment
        do {
            let request = try EnrollmentRequest.decode(body: item.request.body)
            let coreKey = try P256Verifier(canonicalSPKI: item.coreSigningKey)
            let response = try EnrollmentResponse.decode(body: responseBytes)
            verified = try EnrollmentSigning.verifyResponse(
                response, for: request, requestDigest: digest, coreKey: coreKey)
            let published = try replica.completeEnrollment(
                EnrollmentCompletion(
                    datasetID: request.datasetID, deviceID: verified.result.deviceID,
                    enrollmentID: request.enrollmentID,
                    requestDigest: digest, coreURL: item.coreURL, coreSigningKey: item.coreSigningKey,
                    tlsMode: item.policy.mode, tlsHost: item.policy.host, caCertificate: item.policy.caCertificate,
                    intermediates: item.policy.intermediates, roster: response.roster))
            try? pending.delete()
            return CompletedEnrollment(
                deviceID: verified.result.deviceID, roster: verified.roster, published: published)
        } catch let error as EnrollmentVerificationError {
            throw .unverifiableResult(error)
        } catch let error as ReplicaStoreError {
            throw .replica(error)
        } catch let error as OperationEnvelopeError {
            throw .unverifiableResult(.malformed(error))
        } catch {
            throw .unverifiableResult(.invalidKey)
        }
    }

    /// The policy for ordinary connections after enrollment: the trusted host, mode and anchors, with the pins the
    /// newest verified roster authorizes now.
    public static func policy(for trust: ReplicaTrustState, roster: TrustRoster, at time: Int64) -> CoreTLSPolicy {
        CoreTLSPolicy(
            host: trust.tlsHost, mode: trust.tlsMode, pins: roster.acceptedPins(at: time),
            caCertificate: trust.caCertificate, intermediates: trust.intermediates)
    }
}
