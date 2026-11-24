// The per-device re-anchoring text `lisa-reanchor:2:` (plan §8.1.4, §8.5.6), decoded under the shared owner-text rule.

import LisaSyncProtocol

/// What `lisa core device reanchor-text` shows for one device after loss of Core's signer: dataset, target device,
/// active epoch, confirmation sequence and the SHA-256 of the exact signed confirmation, Core's new signing key with
/// its full fingerprint, and the length and SHA-256 of the public proof the owner transfers beside it.
public struct ReanchorText: Hashable, Sendable {
    public static let prefix = "lisa-reanchor:2:"
    public static let version: Int64 = 2
    /// The fingerprint-only earlier format, refused before any trust change.
    public static let outdatedPrefixes = ["lisa-reanchor:1:"]

    public let datasetID: Identifier128
    public let deviceID: Identifier128
    public let epochID: Identifier128
    public let confirmationSequence: Int64
    public let confirmationDigest: Digest256
    public let coreSigningKey: CoreSigningIdentity
    public let proofLength: Int64
    public let proofDigest: Digest256

    /// - Throws: `TrustError.invalidField` for a negative sequence or a non-positive proof length.
    public init(
        datasetID: Identifier128, deviceID: Identifier128, epochID: Identifier128, confirmationSequence: Int64,
        confirmationDigest: Digest256, coreSigningKey: CoreSigningIdentity, proofLength: Int64, proofDigest: Digest256
    ) throws(TrustError) {
        guard confirmationSequence >= 0 else { throw .invalidField("confirmationSequence") }
        guard proofLength > 0 else { throw .invalidField("proofLength") }
        self.datasetID = datasetID
        self.deviceID = deviceID
        self.epochID = epochID
        self.confirmationSequence = confirmationSequence
        self.confirmationDigest = confirmationDigest
        self.coreSigningKey = coreSigningKey
        self.proofLength = proofLength
        self.proofDigest = proofDigest
    }

    /// The owner text.
    public func encoded() throws(TrustError) -> String {
        try OwnerTextCodec.encode(
            prefix: Self.prefix, version: Self.version,
            fields: [
                ("datasetID", .string(datasetID.hex)), ("deviceID", .string(deviceID.hex)),
                ("epochID", .string(epochID.hex)), ("confirmationSequence", .integer(confirmationSequence)),
                ("confirmationDigest", .string(confirmationDigest.hex)),
                ("coreSigningSPKI", .string(StrictBase64URL.encode(coreSigningKey.spkiDER))),
                ("coreSigningFingerprint", .string(coreSigningKey.fingerprint.hex)),
                ("proofLength", .integer(proofLength)), ("proofDigest", .string(proofDigest.hex)),
            ])
    }

    /// Decodes and validates a re-anchoring text under the shared rule.
    public static func decode(_ text: String) throws(TrustError) -> ReanchorText {
        var reader = try OwnerTextCodec.decode(
            text, prefix: prefix, version: version, outdatedPrefixes: outdatedPrefixes)
        do {
            let dataset = try PairingText.identifier(reader.string("datasetID"), "datasetID")
            let device = try PairingText.identifier(reader.string("deviceID"), "deviceID")
            let epoch = try PairingText.identifier(reader.string("epochID"), "epochID")
            let sequence = try reader.integer("confirmationSequence")
            let confirmation = try PairingText.digest(reader.string("confirmationDigest"), "confirmationDigest")
            let spki = try reader.bytes("coreSigningSPKI")
            let fingerprint = try PairingText.digest(reader.string("coreSigningFingerprint"), "coreSigningFingerprint")
            let length = try reader.integer("proofLength")
            let proof = try PairingText.digest(reader.string("proofDigest"), "proofDigest")
            try reader.finish()
            return try ReanchorText(
                datasetID: dataset, deviceID: device, epochID: epoch, confirmationSequence: sequence,
                confirmationDigest: confirmation,
                coreSigningKey: CoreSigningIdentity(spkiDER: spki, fingerprint: fingerprint), proofLength: length,
                proofDigest: proof)
        } catch let error as TrustError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .payloadEncoding
        }
    }
}
