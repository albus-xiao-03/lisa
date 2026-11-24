// Large artifacts, paged and bound as a whole (plan §8.1.3, §8.4.3): the signed header and the page wire unit.

/// The header Core signs for a paged artifact: its type, dataset, epoch, version, page count and the Merkle root of
/// the ordered pages (RFC 6962 hashing: leaf `SHA-256(0x00 ‖ page)`, node `SHA-256(0x01 ‖ left ‖ right)`).
public struct PagedArtifactHeader: Hashable, Sendable {
    /// The largest page, so every page fits one frame and one HTTP message (plan §8.16.2).
    public static let maximumPageBytes = 524_288

    public let artifactType: String
    public let datasetID: Identifier128
    public let epochID: Identifier128
    public let version: Int64
    public let pageCount: Int64
    public let merkleRoot: Digest256

    public init(
        artifactType: String, datasetID: Identifier128, epochID: Identifier128, version: Int64, pageCount: Int64,
        merkleRoot: Digest256
    ) throws(OperationEnvelopeError) {
        guard WireText.isToken(artifactType, length: WireText.tokenLength) else { throw .invalidField("artifactType") }
        guard version >= 0 else { throw .invalidField("version") }
        guard pageCount >= 1 else { throw .invalidField("pageCount") }
        self.artifactType = artifactType
        self.datasetID = datasetID
        self.epochID = epochID
        self.version = version
        self.pageCount = pageCount
        self.merkleRoot = merkleRoot
    }

    /// The canonical signed body.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            let object = try CanonicalObject([
                ("artifactType", .string(artifactType)), ("datasetID", .string(datasetID.hex)),
                ("epochID", .string(epochID.hex)), ("version", .integer(version)), ("pageCount", .integer(pageCount)),
                ("merkleRoot", .string(merkleRoot.hex)),
            ])
            return try CanonicalEncoder.encode(.object(object), limits: .operationBody)
        } catch {
            throw .encoding(error)
        }
    }

    /// Decodes a header body strictly.
    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> PagedArtifactHeader {
        let value: CanonicalValue
        do {
            value = try CanonicalDecoder.decode(body, limits: .operationBody)
        } catch {
            throw .encoding(error)
        }
        guard case .object(let object) = value else { throw .field(.notAnObject) }
        var reader = CanonicalFieldReader(object: object)
        do {
            let header = try PagedArtifactHeader(
                artifactType: reader.string("artifactType"),
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "datasetID"),
                epochID: EnvelopeFields.identifier(reader.string("epochID"), "epochID"),
                version: reader.integer("version"), pageCount: reader.integer("pageCount"),
                merkleRoot: EnvelopeFields.digest(reader.string("merkleRoot"), "merkleRoot"))
            try reader.finish()
            return header
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("header")
        }
    }
}

/// One page as it travels: its index, its bytes and its inclusion proof (the audit path, leaf side first).
public struct PagedArtifactPage: Hashable, Sendable {
    public let index: Int64
    public let bytes: [UInt8]
    public let proof: [Digest256]

    public init(index: Int64, bytes: [UInt8], proof: [Digest256]) throws(OperationEnvelopeError) {
        guard index >= 0 else { throw .invalidField("index") }
        guard bytes.count <= PagedArtifactHeader.maximumPageBytes else { throw .invalidField("page") }
        guard proof.count <= 63 else { throw .invalidField("proof") }
        self.index = index
        self.bytes = bytes
        self.proof = proof
    }
}
