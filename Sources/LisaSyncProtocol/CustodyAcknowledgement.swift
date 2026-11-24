// A peer's custody acknowledgement (plan §8.6.1, §8.7): the receiver of an operation signs, with its operation key,
// that it durably holds these exact bytes. It is evidence of peer custody only, "Also held by <device>", and never of
// Core commitment (R2-L15, R2-SYNC-04). The holder signs `"lisa-r2-custody-v1\n"` ‖ the canonical body.

/// What a custody acknowledgement says.
public struct CustodyAcknowledgement: Hashable, Sendable {
    /// The largest canonical body accepted.
    public static let maximumBytes = 1_024

    public let datasetID: Identifier128
    /// The device that holds the bytes and signs.
    public let holderDeviceID: Identifier128
    public let operationID: Identifier128
    /// SHA-256 of the operation's complete canonical signed body (§8.2.1).
    public let digest: Digest256
    /// When the holder stored the bytes, in Unix milliseconds: display and audit only.
    public let acknowledgedAt: Int64

    public init(
        datasetID: Identifier128, holderDeviceID: Identifier128, operationID: Identifier128, digest: Digest256,
        acknowledgedAt: Int64
    ) throws(OperationEnvelopeError) {
        guard acknowledgedAt >= 0 else { throw .invalidField("custody.acknowledgedAt") }
        self.datasetID = datasetID
        self.holderDeviceID = holderDeviceID
        self.operationID = operationID
        self.digest = digest
        self.acknowledgedAt = acknowledgedAt
    }

    /// The canonical body the holder signs.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            let object = try CanonicalObject([
                ("datasetID", .string(datasetID.hex)), ("holderDeviceID", .string(holderDeviceID.hex)),
                ("operationID", .string(operationID.hex)), ("digest", .string(digest.hex)),
                ("acknowledgedAt", .integer(acknowledgedAt)),
            ])
            return try CanonicalEncoder.encode(.object(object), limits: CanonicalLimits(maxBytes: Self.maximumBytes))
        } catch {
            throw .encoding(error)
        }
    }

    /// Decodes a body strictly: canonical JSON within 1 KiB, every field by its rules, no unknown fields.
    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> CustodyAcknowledgement {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: Self.maximumBytes)))
            let acknowledgement = try CustodyAcknowledgement(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "custody.datasetID"),
                holderDeviceID: EnvelopeFields.identifier(reader.string("holderDeviceID"), "custody.holderDeviceID"),
                operationID: EnvelopeFields.identifier(reader.string("operationID"), "custody.operationID"),
                digest: EnvelopeFields.digest(reader.string("digest"), "custody.digest"),
                acknowledgedAt: reader.integer("acknowledgedAt"))
            try reader.finish()
            return acknowledgement
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("custody")
        }
    }
}

/// A custody acknowledgement as it travels: its exact canonical body and the holder's raw 64-byte signature.
public struct SignedCustodyAcknowledgement: Hashable, Sendable {
    public let body: [UInt8]
    public let signature: [UInt8]

    public init(body: [UInt8], signature: [UInt8]) throws(OperationEnvelopeError) {
        guard body.count <= CustodyAcknowledgement.maximumBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: CustodyAcknowledgement.maximumBytes))
        }
        guard signature.count == 64 else { throw .invalidField("custody.signature") }
        self.body = body
        self.signature = signature
    }

    /// The acknowledgement, decoded strictly; says nothing about who signed it.
    public func acknowledgement() throws(OperationEnvelopeError) -> CustodyAcknowledgement {
        try CustodyAcknowledgement.decode(body: body)
    }
}
