// The enrollment messages (plan §8.1.2 steps 3–6): the device's signed request, Core's signed result, the device
// authorization record and the immutable response that binds them with the new roster, and Core's token-free TLS
// anchors bundle. Each signed body is canonical JSON (§8.16.1) and travels as base64url with its raw signature.
//
// The request's exact bytes contain the token, so they are secret-bearing: the device keeps them only in its pending
// retry item, Core never stores them, and `description` never shows them.

/// How a device evaluates Core's TLS certificate (§8.1.2 step 3).
public enum CoreTLSMode: String, Hashable, Sendable {
    /// The owner's CA is the only anchor, and the leaf's key must be an authorized pin.
    case ca
    /// The pinned leaf is the only anchor.
    case pin
}

/// A signed body and its raw 64-byte signature, as they travel.
public struct SignedBody: Hashable, Sendable {
    public let body: [UInt8]
    public let signature: [UInt8]

    public init(body: [UInt8], signature: [UInt8], maximumBytes: Int) throws(OperationEnvelopeError) {
        guard !body.isEmpty, body.count <= maximumBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: maximumBytes))
        }
        guard signature.count == 64 else { throw .invalidField("signature") }
        self.body = body
        self.signature = signature
    }

    /// `{"body", "signature"}`, both base64url.
    public func canonicalValue() -> CanonicalValue {
        (try? CanonicalObject([
            ("body", .string(StrictBase64URL.encode(body))), ("signature", .string(StrictBase64URL.encode(signature))),
        ])).map(CanonicalValue.object) ?? .null
    }

    public static func decode(_ value: CanonicalValue, maximumBytes: Int) throws(OperationEnvelopeError) -> SignedBody {
        do {
            var reader = try CanonicalFieldReader(value)
            let signed = try SignedBody(
                body: reader.bytes("body"), signature: reader.bytes("signature"), maximumBytes: maximumBytes)
            try reader.finish()
            return signed
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("signed")
        }
    }
}

/// What the device signs and sends with the token (§8.1.2 step 4).
public struct EnrollmentRequest: Hashable, Sendable, CustomStringConvertible {
    public static let maximumBytes = 16_384
    public static let tokenBytes = 32

    public let enrollmentID: Identifier128
    /// The 32-byte token from the owner text: secret.
    public let token: [UInt8]
    public let datasetID: Identifier128
    public let trustMode: CoreTLSMode
    public let leafPin: Digest256
    /// In `ca` mode, the owner CA's digest from the owner text.
    public let caDigest: Digest256?
    /// The full fingerprint of the Core signing key the owner text named.
    public let issuerFingerprint: Digest256
    public let deviceName: String
    public let deviceClass: RosterDevice.DeviceClass
    /// Canonical SubjectPublicKeyInfo DER of the new operation-signing key, which signs this request.
    public let operationKey: [UInt8]
    /// Canonical SubjectPublicKeyInfo DER of the new device export key.
    public let exportKey: [UInt8]
    /// SHA-256 of the device-generated 256-bit Core credential; Core stores only this.
    public let credentialVerifier: Digest256
    /// The incarnation that starts the device's chain.
    public let incarnationID: Identifier128
    public let createdAt: Int64

    public init(
        enrollmentID: Identifier128, token: [UInt8], datasetID: Identifier128, trustMode: CoreTLSMode,
        leafPin: Digest256, caDigest: Digest256?, issuerFingerprint: Digest256, deviceName: String,
        deviceClass: RosterDevice.DeviceClass, operationKey: [UInt8], exportKey: [UInt8],
        credentialVerifier: Digest256, incarnationID: Identifier128, createdAt: Int64
    ) throws(OperationEnvelopeError) {
        guard token.count == Self.tokenBytes else { throw .invalidField("enrollment.token") }
        guard (trustMode == .ca) == (caDigest != nil) else { throw .invalidField("enrollment.caDigest") }
        guard RosterDevice.isValidName(deviceName) else { throw .invalidField("enrollment.deviceName") }
        guard (1...256).contains(operationKey.count), (1...256).contains(exportKey.count) else {
            throw .invalidField("enrollment.keys")
        }
        self.enrollmentID = enrollmentID
        self.token = token
        self.datasetID = datasetID
        self.trustMode = trustMode
        self.leafPin = leafPin
        self.caDigest = caDigest
        self.issuerFingerprint = issuerFingerprint
        self.deviceName = deviceName
        self.deviceClass = deviceClass
        self.operationKey = operationKey
        self.exportKey = exportKey
        self.credentialVerifier = credentialVerifier
        self.incarnationID = incarnationID
        self.createdAt = createdAt
    }

    public var description: String { "EnrollmentRequest(enrollment \(enrollmentID), token redacted)" }

    /// The canonical body the device signs: secret-bearing.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        var fields: [(String, CanonicalValue)] = [
            ("enrollmentID", .string(enrollmentID.hex)), ("token", .string(StrictBase64URL.encode(token))),
            ("datasetID", .string(datasetID.hex)), ("trustMode", .string(trustMode.rawValue)),
            ("leafPin", .string(leafPin.hex)), ("issuerFingerprint", .string(issuerFingerprint.hex)),
            ("deviceName", .string(deviceName)), ("deviceClass", .string(deviceClass.rawValue)),
            ("operationKey", .string(StrictBase64URL.encode(operationKey))),
            ("exportKey", .string(StrictBase64URL.encode(exportKey))),
            ("credentialVerifier", .string(credentialVerifier.hex)), ("incarnationID", .string(incarnationID.hex)),
            ("createdAt", .integer(createdAt)),
        ]
        if let caDigest { fields.append(("caDigest", .string(caDigest.hex))) }
        return try EnrollmentCodec.encode(fields, maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> EnrollmentRequest {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            guard let mode = CoreTLSMode(rawValue: try reader.string("trustMode")),
                let deviceClass = RosterDevice.DeviceClass(rawValue: try reader.string("deviceClass"))
            else { throw OperationEnvelopeError.invalidField("enrollment.request") }
            return try EnrollmentRequest(
                enrollmentID: EnvelopeFields.identifier(reader.string("enrollmentID"), "enrollment.enrollmentID"),
                token: reader.bytes("token"),
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "enrollment.datasetID"),
                trustMode: mode, leafPin: EnvelopeFields.digest(reader.string("leafPin"), "enrollment.leafPin"),
                caDigest: reader.optionalString("caDigest").map { hex throws in
                    try EnvelopeFields.digest(hex, "enrollment.caDigest")
                },
                issuerFingerprint: EnvelopeFields.digest(
                    reader.string("issuerFingerprint"), "enrollment.issuerFingerprint"),
                deviceName: reader.string("deviceName"), deviceClass: deviceClass,
                operationKey: reader.bytes("operationKey"), exportKey: reader.bytes("exportKey"),
                credentialVerifier: EnvelopeFields.digest(
                    reader.string("credentialVerifier"), "enrollment.credentialVerifier"),
                incarnationID: EnvelopeFields.identifier(reader.string("incarnationID"), "enrollment.incarnationID"),
                createdAt: reader.integer("createdAt"))
        }
    }
}

/// Core's signed result (§8.1.2 step 5.7), binding the dataset, the enrollment, the issuing key, the exact signed
/// request bytes, the assigned device ID, the enrolled keys and the returned roster and authorization record.
public struct EnrollmentResult: Hashable, Sendable {
    public static let maximumBytes = 8_192

    public let datasetID: Identifier128
    public let enrollmentID: Identifier128
    public let issuerFingerprint: Digest256
    /// SHA-256 of the exact signed request body.
    public let requestDigest: Digest256
    public let deviceID: Identifier128
    public let operationKey: [UInt8]
    public let exportKey: [UInt8]
    /// SHA-256 of the returned roster's signed header body, which binds every page.
    public let rosterDigest: Digest256
    /// SHA-256 of the returned authorization record's body.
    public let authorizationDigest: Digest256
    public let issuedAt: Int64

    public init(
        datasetID: Identifier128, enrollmentID: Identifier128, issuerFingerprint: Digest256, requestDigest: Digest256,
        deviceID: Identifier128, operationKey: [UInt8], exportKey: [UInt8], rosterDigest: Digest256,
        authorizationDigest: Digest256, issuedAt: Int64
    ) {
        self.datasetID = datasetID
        self.enrollmentID = enrollmentID
        self.issuerFingerprint = issuerFingerprint
        self.requestDigest = requestDigest
        self.deviceID = deviceID
        self.operationKey = operationKey
        self.exportKey = exportKey
        self.rosterDigest = rosterDigest
        self.authorizationDigest = authorizationDigest
        self.issuedAt = issuedAt
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)), ("enrollmentID", .string(enrollmentID.hex)),
                ("issuerFingerprint", .string(issuerFingerprint.hex)), ("requestDigest", .string(requestDigest.hex)),
                ("deviceID", .string(deviceID.hex)), ("operationKey", .string(StrictBase64URL.encode(operationKey))),
                ("exportKey", .string(StrictBase64URL.encode(exportKey))), ("rosterDigest", .string(rosterDigest.hex)),
                ("authorizationDigest", .string(authorizationDigest.hex)), ("issuedAt", .integer(issuedAt)),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> EnrollmentResult {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            EnrollmentResult(
                datasetID: try EnvelopeFields.identifier(reader.string("datasetID"), "result.datasetID"),
                enrollmentID: try EnvelopeFields.identifier(reader.string("enrollmentID"), "result.enrollmentID"),
                issuerFingerprint: try EnvelopeFields.digest(
                    reader.string("issuerFingerprint"), "result.issuerFingerprint"),
                requestDigest: try EnvelopeFields.digest(reader.string("requestDigest"), "result.requestDigest"),
                deviceID: try EnvelopeFields.identifier(reader.string("deviceID"), "result.deviceID"),
                operationKey: try reader.bytes("operationKey"), exportKey: try reader.bytes("exportKey"),
                rosterDigest: try EnvelopeFields.digest(reader.string("rosterDigest"), "result.rosterDigest"),
                authorizationDigest: try EnvelopeFields.digest(
                    reader.string("authorizationDigest"), "result.authorizationDigest"),
                issuedAt: try reader.integer("issuedAt"))
        }
    }
}

/// Core's authorization record for one device: its membership and capabilities at a roster version.
public struct DeviceAuthorization: Hashable, Sendable {
    public static let maximumBytes = 4_096

    public let datasetID: Identifier128
    public let epochID: Identifier128
    public let deviceID: Identifier128
    public let rosterVersion: Int64
    public let operationKey: [UInt8]
    /// Strictly ascending capability tokens.
    public let capabilities: [String]
    public let issuedAt: Int64

    public init(
        datasetID: Identifier128, epochID: Identifier128, deviceID: Identifier128, rosterVersion: Int64,
        operationKey: [UInt8], capabilities: [String], issuedAt: Int64
    ) throws(OperationEnvelopeError) {
        guard rosterVersion >= 1 else { throw .invalidField("authorization.rosterVersion") }
        guard capabilities.allSatisfy({ WireText.isToken($0, length: 1...64) }),
            zip(capabilities, capabilities.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw .invalidField("authorization.capabilities") }
        self.datasetID = datasetID
        self.epochID = epochID
        self.deviceID = deviceID
        self.rosterVersion = rosterVersion
        self.operationKey = operationKey
        self.capabilities = capabilities
        self.issuedAt = issuedAt
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)), ("epochID", .string(epochID.hex)),
                ("deviceID", .string(deviceID.hex)), ("rosterVersion", .integer(rosterVersion)),
                ("operationKey", .string(StrictBase64URL.encode(operationKey))),
                ("capabilities", .array(capabilities.map { .string($0) })), ("issuedAt", .integer(issuedAt)),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> DeviceAuthorization {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            let capabilities = try reader.array("capabilities").map { value in
                guard case .string(let text) = value else {
                    throw OperationEnvelopeError.invalidField("authorization.capabilities")
                }
                return text
            }
            return try DeviceAuthorization(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "authorization.datasetID"),
                epochID: EnvelopeFields.identifier(reader.string("epochID"), "authorization.epochID"),
                deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "authorization.deviceID"),
                rosterVersion: reader.integer("rosterVersion"), operationKey: reader.bytes("operationKey"),
                capabilities: capabilities, issuedAt: reader.integer("issuedAt"))
        }
    }
}

/// The immutable response Core stores for 7 days and returns to an exact retry: the signed result, the new roster and
/// the signed authorization record. It holds no part of the request.
public struct EnrollmentResponse: Hashable, Sendable {
    public static let maximumBytes = 524_288

    public let result: SignedBody
    public let roster: SignedRoster
    public let authorization: SignedBody

    public init(result: SignedBody, roster: SignedRoster, authorization: SignedBody) {
        self.result = result
        self.roster = roster
        self.authorization = authorization
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("result", result.canonicalValue()), ("roster", try roster.canonicalValue()),
                ("authorization", authorization.canonicalValue()),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> EnrollmentResponse {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            EnrollmentResponse(
                result: try SignedBody.decode(try reader.value("result"), maximumBytes: EnrollmentResult.maximumBytes),
                roster: try SignedRoster.decode(try reader.value("roster")),
                authorization: try SignedBody.decode(
                    try reader.value("authorization"), maximumBytes: DeviceAuthorization.maximumBytes))
        }
    }
}

/// Core's token-free TLS anchors bundle (§8.1.2 step 3): the owner CA certificate and every intermediate Core is
/// configured with, as DER, signed by Core's signing key. The body depends only on the dataset and the configured
/// certificates, so its digest, which the roster carries, stays the same across Core restarts.
public struct TLSAnchorsBundle: Hashable, Sendable {
    public static let maximumBytes = 65_536
    public static let maximumIntermediates = 4

    public let datasetID: Identifier128
    public let caCertificate: [UInt8]
    /// From the leaf's issuer upward.
    public let intermediates: [[UInt8]]

    public init(datasetID: Identifier128, caCertificate: [UInt8], intermediates: [[UInt8]])
        throws(OperationEnvelopeError)
    {
        guard !caCertificate.isEmpty, intermediates.count <= Self.maximumIntermediates,
            intermediates.allSatisfy({ !$0.isEmpty })
        else { throw .invalidField("anchors") }
        self.datasetID = datasetID
        self.caCertificate = caCertificate
        self.intermediates = intermediates
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)),
                ("caCertificate", .string(StrictBase64URL.encode(caCertificate))),
                ("intermediates", .array(intermediates.map { .string(StrictBase64URL.encode($0)) })),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> TLSAnchorsBundle {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            let intermediates = try reader.array("intermediates").map { value in
                guard case .string(let text) = value, let der = try? StrictBase64URL.decode(text) else {
                    throw OperationEnvelopeError.invalidField("anchors.intermediates")
                }
                return der
            }
            return try TLSAnchorsBundle(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "anchors.datasetID"),
                caCertificate: reader.bytes("caCertificate"), intermediates: intermediates)
        }
    }
}

/// The wire forms of the enrollment routes: `POST /v2/enrollments` carries `{"request": {"body", "signature"}}` and
/// answers the response body; `GET /v2/trust/tls-anchors` answers `{"bundle": {"body", "signature"}}`; `GET /v2/trust`
/// answers `{"roster": …}`.
public enum EnrollmentWire {
    public static func requestBody(_ signed: SignedBody) throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode([("request", signed.canonicalValue())], maximumBytes: 32_768)
    }

    public static func request(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> SignedBody {
        try EnrollmentCodec.decode(body, maximumBytes: 32_768) { reader throws in
            try SignedBody.decode(try reader.value("request"), maximumBytes: EnrollmentRequest.maximumBytes)
        }
    }

    public static func anchorsBody(_ signed: SignedBody) throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [("bundle", signed.canonicalValue())], maximumBytes: 2 * TLSAnchorsBundle.maximumBytes)
    }

    public static func anchors(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> SignedBody {
        try EnrollmentCodec.decode(body, maximumBytes: 2 * TLSAnchorsBundle.maximumBytes) { reader throws in
            try SignedBody.decode(try reader.value("bundle"), maximumBytes: TLSAnchorsBundle.maximumBytes)
        }
    }

    public static func rosterBody(_ roster: SignedRoster) throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode([("roster", try roster.canonicalValue())], maximumBytes: SyncWire.maximumBodyBytes)
    }

    public static func roster(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> SignedRoster {
        try EnrollmentCodec.decode(body, maximumBytes: SyncWire.maximumBodyBytes) { reader throws in
            try SignedRoster.decode(try reader.value("roster"))
        }
    }
}

/// Canonical encoding and strict decoding shared by the enrollment messages.
enum EnrollmentCodec {
    static func encode(_ fields: [(String, CanonicalValue)], maximumBytes: Int) throws(OperationEnvelopeError)
        -> [UInt8]
    {
        do {
            return try CanonicalEncoder.encode(
                .object(try CanonicalObject(fields)), limits: CanonicalLimits(maxBytes: maximumBytes))
        } catch {
            throw .encoding(error)
        }
    }

    static func decode<T>(_ body: [UInt8], maximumBytes: Int, _ read: (inout CanonicalFieldReader) throws -> T)
        throws(OperationEnvelopeError) -> T
    {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: maximumBytes)))
            let value = try read(&reader)
            try reader.finish()
            return value
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("enrollment")
        }
    }
}
