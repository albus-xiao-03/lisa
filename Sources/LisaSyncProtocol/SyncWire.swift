// The v2 sync messages on the direct HTTPS path (plan §8.12.1, §8.6.5): canonical JSON bodies (§8.16.1), exact signed
// bytes carried as strict base64url. `POST /v2/operations` takes at most 100 signed operations and answers one outcome
// each, in order; `POST /v2/receipts/lookup` takes at most 100 operation IDs and answers each one's current receipt or
// none; `GET /v2/changes` answers one signed page or none; `GET /v2/capabilities` names the API version, the dataset,
// the epoch, the newest commit position and Core's features.

/// Encoders and strict decoders of the v2 sync messages.
public enum SyncWire {
    /// The most operations or IDs one request carries.
    public static let maximumItems = 100
    /// The largest body a message may have; a server's own request limit may be lower.
    public static let maximumBodyBytes = 524_288
    public static let apiVersion = "2.0"

    /// What Core did with one submitted operation.
    public enum Outcome: Hashable, Sendable {
        case receipted(SignedCoreReceipt)
        case duplicate(SignedCoreReceipt)
        case identityReuse
        case sequenceReuse
        /// Refused before anything was stored, with Core's reason; no receipt.
        case unverified(String)
    }

    /// What `GET /v2/capabilities` says.
    public struct Capabilities: Hashable, Sendable {
        public let apiVersion: String
        public let datasetID: Identifier128
        public let epochID: Identifier128
        public let head: Int64
        /// Core's features, strictly ascending tokens; a client may require any of them (§8.12.1).
        public let features: [String]

        public init(
            apiVersion: String, datasetID: Identifier128, epochID: Identifier128, head: Int64, features: [String] = []
        ) {
            self.apiVersion = apiVersion
            self.datasetID = datasetID
            self.epochID = epochID
            self.head = head
            self.features = features
        }

        /// The API's major version, the part before the first dot.
        public var majorVersion: String { SyncWire.majorVersion(of: apiVersion) }
    }

    /// The major version of an API version text, the part before the first dot.
    public static func majorVersion(of version: String) -> String {
        String(version.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    // MARK: - Operations

    public static func submissionBody(_ operations: [SignedOperation]) throws(OperationEnvelopeError) -> [UInt8] {
        guard !operations.isEmpty, operations.count <= maximumItems else { throw .invalidField("wire.operations") }
        return try encode([("operations", .array(operations.map { signed($0.body, $0.signature) }))])
    }

    public static func operations(fromSubmission body: [UInt8]) throws(OperationEnvelopeError) -> [SignedOperation] {
        try decode(body) { reader throws in
            let values = try reader.array("operations")
            guard !values.isEmpty, values.count <= maximumItems else {
                throw OperationEnvelopeError.invalidField("wire.operations")
            }
            return try values.map { value in
                let (body, signature) = try signedParts(value)
                return try SignedOperation(body: body, signature: signature)
            }
        }
    }

    public static func outcomesBody(_ outcomes: [Outcome]) throws(OperationEnvelopeError) -> [UInt8] {
        let values: [CanonicalValue] = outcomes.map { outcome in
            var fields: [(String, CanonicalValue)]
            switch outcome {
            case .receipted(let receipt):
                fields = [("outcome", .string("receipted")), ("receipt", signed(receipt.body, receipt.signature))]
            case .duplicate(let receipt):
                fields = [("outcome", .string("duplicate")), ("receipt", signed(receipt.body, receipt.signature))]
            case .identityReuse: fields = [("outcome", .string("identity_reuse"))]
            case .sequenceReuse: fields = [("outcome", .string("sequence_reuse"))]
            case .unverified(let reason): fields = [("outcome", .string("unverified")), ("reason", .string(reason))]
            }
            return (try? CanonicalObject(fields)).map(CanonicalValue.object) ?? .null
        }
        return try encode([("outcomes", .array(values))])
    }

    public static func outcomes(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> [Outcome] {
        try decode(body) { reader throws in
            try reader.array("outcomes").map { value in
                var item = try CanonicalFieldReader(value)
                let kind = try item.string("outcome")
                let outcome: Outcome
                switch kind {
                case "receipted", "duplicate":
                    let (body, signature) = try signedParts(try item.value("receipt"))
                    let receipt = try SignedCoreReceipt(body: body, signature: signature)
                    outcome = kind == "receipted" ? .receipted(receipt) : .duplicate(receipt)
                case "identity_reuse": outcome = .identityReuse
                case "sequence_reuse": outcome = .sequenceReuse
                case "unverified": outcome = .unverified(try item.string("reason"))
                default: throw OperationEnvelopeError.invalidField("wire.outcome")
                }
                try item.finish()
                return outcome
            }
        }
    }

    // MARK: - Receipt lookup

    public static func lookupBody(_ operationIDs: [Identifier128]) throws(OperationEnvelopeError) -> [UInt8] {
        guard !operationIDs.isEmpty, operationIDs.count <= maximumItems else {
            throw .invalidField("wire.operationIDs")
        }
        return try encode([("operationIDs", .array(operationIDs.map { .string($0.hex) }))])
    }

    public static func lookupIDs(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> [Identifier128] {
        try decode(body) { reader throws in
            let values = try reader.array("operationIDs")
            guard !values.isEmpty, values.count <= maximumItems else {
                throw OperationEnvelopeError.invalidField("wire.operationIDs")
            }
            return try values.map { value in
                guard case .string(let hex) = value else {
                    throw OperationEnvelopeError.invalidField("wire.operationIDs")
                }
                return try EnvelopeFields.identifier(hex, "wire.operationIDs")
            }
        }
    }

    public static func receiptsBody(_ receipts: [(operationID: Identifier128, receipt: SignedCoreReceipt?)])
        throws(OperationEnvelopeError) -> [UInt8]
    {
        let values: [CanonicalValue] = receipts.map { item in
            var fields: [(String, CanonicalValue)] = [("operationID", .string(item.operationID.hex))]
            if let receipt = item.receipt { fields.append(("receipt", signed(receipt.body, receipt.signature))) }
            return (try? CanonicalObject(fields)).map(CanonicalValue.object) ?? .null
        }
        return try encode([("receipts", .array(values))])
    }

    public static func receipts(fromBody body: [UInt8]) throws(OperationEnvelopeError)
        -> [(operationID: Identifier128, receipt: SignedCoreReceipt?)]
    {
        try decode(body) { reader throws in
            try reader.array("receipts").map { value in
                var item = try CanonicalFieldReader(value)
                let id = try EnvelopeFields.identifier(try item.string("operationID"), "wire.receipts")
                var receipt: SignedCoreReceipt?
                if let signed = item.optionalValue("receipt") {
                    let (body, signature) = try signedParts(signed)
                    receipt = try SignedCoreReceipt(body: body, signature: signature)
                }
                try item.finish()
                return (id, receipt)
            }
        }
    }

    // MARK: - Changes and capabilities

    public static func pageBody(_ page: SignedChangePage?) throws(OperationEnvelopeError) -> [UInt8] {
        try encode(page.map { [("page", signed($0.body, $0.signature))] } ?? [])
    }

    public static func page(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> SignedChangePage? {
        try decode(body) { reader throws in
            guard let value = reader.optionalValue("page") else { return nil }
            let (body, signature) = try signedParts(value)
            return try SignedChangePage(body: body, signature: signature)
        }
    }

    public static func capabilitiesBody(_ capabilities: Capabilities) throws(OperationEnvelopeError) -> [UInt8] {
        try encode([
            ("apiVersion", .string(capabilities.apiVersion)), ("datasetID", .string(capabilities.datasetID.hex)),
            ("epochID", .string(capabilities.epochID.hex)), ("head", .integer(capabilities.head)),
            ("features", .array(capabilities.features.map { .string($0) })),
        ])
    }

    public static func capabilities(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> Capabilities {
        try decode(body) { reader throws in
            let features = try reader.array("features").map { value in
                guard case .string(let name) = value, WireText.isToken(name, length: 1...64) else {
                    throw OperationEnvelopeError.invalidField("wire.features")
                }
                return name
            }
            guard zip(features, features.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw OperationEnvelopeError.invalidField("wire.features")
            }
            return Capabilities(
                apiVersion: try reader.string("apiVersion"),
                datasetID: try EnvelopeFields.identifier(try reader.string("datasetID"), "wire.datasetID"),
                epochID: try EnvelopeFields.identifier(try reader.string("epochID"), "wire.epochID"),
                head: try reader.integer("head"), features: features)
        }
    }

    // MARK: - Helpers

    static func signed(_ body: [UInt8], _ signature: [UInt8]) -> CanonicalValue {
        (try? CanonicalObject([
            ("body", .string(StrictBase64URL.encode(body))), ("signature", .string(StrictBase64URL.encode(signature))),
        ])).map(CanonicalValue.object) ?? .null
    }

    static func signedParts(_ value: CanonicalValue) throws -> (body: [UInt8], signature: [UInt8]) {
        var reader = try CanonicalFieldReader(value)
        let parts = (try reader.bytes("body"), try reader.bytes("signature"))
        try reader.finish()
        return parts
    }

    static func encode(_ fields: [(String, CanonicalValue)]) throws(OperationEnvelopeError) -> [UInt8] {
        do {
            return try CanonicalEncoder.encode(
                .object(try CanonicalObject(fields)), limits: CanonicalLimits(maxBytes: maximumBodyBytes))
        } catch {
            throw .encoding(error)
        }
    }

    static func decode<T>(_ body: [UInt8], _ read: (inout CanonicalFieldReader) throws -> T)
        throws(OperationEnvelopeError) -> T
    {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: maximumBodyBytes)))
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
            throw .invalidField("wire")
        }
    }
}
