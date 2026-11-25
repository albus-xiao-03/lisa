// Credential reset (plan §8.1.4): the owner issues a one-time reset token for one device at the administrative
// terminal; the device presents it with a new credential verifier, signed by its existing operation key, and Core
// replaces the verifier atomically. The request carries the token, so it is secret-bearing: `description` never shows
// it. It travels as `{"request": {"body", "signature"}}` (`EnrollmentWire.requestBody`) to
// `POST /v2/devices/current/credential-reset`, which needs no credential: the old one may be lost.

/// A device's signed request to replace its Core credential.
public struct CredentialResetRequest: Hashable, Sendable, CustomStringConvertible {
    public static let maximumBytes = 4_096
    public static let tokenBytes = 32

    public let datasetID: Identifier128
    public let deviceID: Identifier128
    /// The 32-byte reset token the owner issued: secret.
    public let token: [UInt8]
    /// SHA-256 of the device's new 256-bit credential.
    public let newVerifier: Digest256
    public let createdAt: Int64

    public init(
        datasetID: Identifier128, deviceID: Identifier128, token: [UInt8], newVerifier: Digest256, createdAt: Int64
    ) throws(OperationEnvelopeError) {
        guard token.count == Self.tokenBytes else { throw .invalidField("reset.token") }
        self.datasetID = datasetID
        self.deviceID = deviceID
        self.token = token
        self.newVerifier = newVerifier
        self.createdAt = createdAt
    }

    public var description: String { "CredentialResetRequest(device \(deviceID), token redacted)" }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)), ("deviceID", .string(deviceID.hex)),
                ("token", .string(StrictBase64URL.encode(token))), ("newVerifier", .string(newVerifier.hex)),
                ("createdAt", .integer(createdAt)),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> CredentialResetRequest {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            try CredentialResetRequest(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "reset.datasetID"),
                deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "reset.deviceID"),
                token: reader.bytes("token"),
                newVerifier: EnvelopeFields.digest(reader.string("newVerifier"), "reset.newVerifier"),
                createdAt: reader.integer("createdAt"))
        }
    }

    /// Core's answer to a reset it applied: `{"deviceID", "resetAt"}`.
    public static func answerBody(deviceID: Identifier128, resetAt: Int64) throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [("deviceID", .string(deviceID.hex)), ("resetAt", .integer(resetAt))], maximumBytes: 1_024)
    }

    public static func answer(fromBody body: [UInt8]) throws(OperationEnvelopeError)
        -> (deviceID: Identifier128, resetAt: Int64)
    {
        try EnrollmentCodec.decode(body, maximumBytes: 1_024) { reader throws in
            (try EnvelopeFields.identifier(reader.string("deviceID"), "reset.deviceID"), try reader.integer("resetAt"))
        }
    }
}
