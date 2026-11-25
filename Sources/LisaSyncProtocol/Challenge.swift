// Challenges (plan §8.1.5): key-proven requests for devices whose credential verifiers a restore may have rewound.
// `POST /v2/challenges` takes `{"deviceID", "purpose"}` and answers the challenge; the device then signs, with its
// operation key, `"lisa-challenge-v1" ‖ 0x00 ‖ purpose ‖ datasetID ‖ epochID ‖ challengeID ‖ nonce ‖ deviceID ‖ keyID ‖
// SHA-256(request body)` (`ChallengeSigning`), so the signature binds the content it authorizes. The proof travels
// with that body as `{"challengeID", "keyID", "signature"}`.

/// What a challenge may authorize.
public enum ChallengePurpose: String, Hashable, Sendable, CaseIterable {
    case recoveryEvidence = "recovery-evidence"
    /// A device whose key the merged roster knows but that can't accept the restored head (§8.5.3).
    case trustEvidence = "trust-evidence"
    case credentialRefresh = "credential-refresh"
    case ownerImport = "owner-import"
    case legacyLinkLookup = "legacy-link-lookup"
}

/// One challenge as Core issues it.
public struct Challenge: Hashable, Sendable {
    public static let nonceBytes = 32
    public static let lifetimeSeconds: Int64 = 120

    public let challengeID: Identifier128
    public let nonce: [UInt8]
    public let purpose: ChallengePurpose
    public let datasetID: Identifier128
    public let epochID: Identifier128
    public let deviceID: Identifier128
    public let expiresInSeconds: Int64

    public init(
        challengeID: Identifier128, nonce: [UInt8], purpose: ChallengePurpose, datasetID: Identifier128,
        epochID: Identifier128, deviceID: Identifier128, expiresInSeconds: Int64 = Challenge.lifetimeSeconds
    ) throws(OperationEnvelopeError) {
        guard nonce.count == Self.nonceBytes else { throw .invalidField("challenge.nonce") }
        guard (1...3_600).contains(expiresInSeconds) else { throw .invalidField("challenge.expiresInSeconds") }
        self.challengeID = challengeID
        self.nonce = nonce
        self.purpose = purpose
        self.datasetID = datasetID
        self.epochID = epochID
        self.deviceID = deviceID
        self.expiresInSeconds = expiresInSeconds
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("challengeID", .string(challengeID.hex)), ("nonce", .string(StrictBase64URL.encode(nonce))),
                ("purpose", .string(purpose.rawValue)), ("datasetID", .string(datasetID.hex)),
                ("epochID", .string(epochID.hex)), ("deviceID", .string(deviceID.hex)),
                ("expiresInSeconds", .integer(expiresInSeconds)),
            ], maximumBytes: 2_048)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> Challenge {
        try EnrollmentCodec.decode(body, maximumBytes: 2_048) { reader throws in
            guard let purpose = ChallengePurpose(rawValue: try reader.string("purpose")) else {
                throw OperationEnvelopeError.invalidField("challenge.purpose")
            }
            return try Challenge(
                challengeID: EnvelopeFields.identifier(reader.string("challengeID"), "challenge.challengeID"),
                nonce: reader.bytes("nonce"), purpose: purpose,
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "challenge.datasetID"),
                epochID: EnvelopeFields.identifier(reader.string("epochID"), "challenge.epochID"),
                deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "challenge.deviceID"),
                expiresInSeconds: reader.integer("expiresInSeconds"))
        }
    }

    /// The body of `POST /v2/challenges`.
    public static func requestBody(deviceID: Identifier128, purpose: ChallengePurpose) throws(OperationEnvelopeError)
        -> [UInt8]
    {
        try EnrollmentCodec.encode(
            [("deviceID", .string(deviceID.hex)), ("purpose", .string(purpose.rawValue))], maximumBytes: 1_024)
    }

    public static func request(fromBody body: [UInt8]) throws(OperationEnvelopeError)
        -> (deviceID: Identifier128, purpose: ChallengePurpose)
    {
        try EnrollmentCodec.decode(body, maximumBytes: 1_024) { reader throws in
            guard let purpose = ChallengePurpose(rawValue: try reader.string("purpose")) else {
                throw OperationEnvelopeError.invalidField("challenge.purpose")
            }
            return (try EnvelopeFields.identifier(reader.string("deviceID"), "challenge.deviceID"), purpose)
        }
    }
}

/// A device's answer to a challenge, sent with the body it authorizes.
public struct ChallengeProof: Hashable, Sendable {
    public let challengeID: Identifier128
    /// SHA-256 of the signing key's SubjectPublicKeyInfo DER.
    public let keyID: Digest256
    public let signature: [UInt8]

    public init(challengeID: Identifier128, keyID: Digest256, signature: [UInt8]) throws(OperationEnvelopeError) {
        guard signature.count == 64 else { throw .invalidField("challenge.signature") }
        self.challengeID = challengeID
        self.keyID = keyID
        self.signature = signature
    }

    public func canonicalValue() -> CanonicalValue {
        (try? CanonicalObject([
            ("challengeID", .string(challengeID.hex)), ("keyID", .string(keyID.hex)),
            ("signature", .string(StrictBase64URL.encode(signature))),
        ])).map(CanonicalValue.object) ?? .null
    }

    public static func decode(_ value: CanonicalValue) throws(OperationEnvelopeError) -> ChallengeProof {
        do {
            var reader = try CanonicalFieldReader(value)
            let proof = try ChallengeProof(
                challengeID: EnvelopeFields.identifier(reader.string("challengeID"), "challenge.challengeID"),
                keyID: EnvelopeFields.digest(reader.string("keyID"), "challenge.keyID"),
                signature: reader.bytes("signature"))
            try reader.finish()
            return proof
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("challenge.proof")
        }
    }
}
