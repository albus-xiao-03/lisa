// Core's receipt for one operation (plan §8.2.1, R2-SYNC-03). A provisional receipt says the operation waits for
// dependencies and names the missing ones, with no position. A final receipt carries the decision, `accepted`,
// `accepted_with_conflict` or `rejected` with a reason and a recovery hint, and the commit position. Core signs
// `"lisa-r2-receipt-v1\n"` ‖ the canonical body; relays forward exact bytes.

/// What a Core receipt says.
public struct CoreReceipt: Hashable, Sendable {
    public enum Outcome: String, Hashable, Sendable {
        case waitingForDependencies = "waiting_for_dependencies"
        case accepted
        case acceptedWithConflict = "accepted_with_conflict"
        case rejected

        /// Whether the receipt is final.
        public var isFinal: Bool { self != .waitingForDependencies }
    }

    /// The largest canonical body accepted.
    public static let maximumBytes = 16_384
    /// The longest reason code and recovery hint.
    public static let maximumReasonBytes = 64
    public static let maximumHintBytes = 1_024

    public let datasetID: Identifier128
    public let epochID: Identifier128
    public let operationID: Identifier128
    /// SHA-256 of the operation's complete canonical signed body.
    public let digest: Digest256
    public let outcome: Outcome
    /// The commit position: present exactly on final receipts.
    public let position: Int64?
    /// The dependencies still missing, strictly ascending: only on a provisional receipt, which names at least one.
    public let missing: [Identifier128]
    /// A rejection's reason code (`malformed`, `dependency_rejected`, …) and recovery hint: only on `rejected`.
    public let reason: String?
    public let recoveryHint: String?

    public init(
        datasetID: Identifier128, epochID: Identifier128, operationID: Identifier128, digest: Digest256,
        outcome: Outcome, position: Int64?, missing: [Identifier128] = [], reason: String? = nil,
        recoveryHint: String? = nil
    ) throws(OperationEnvelopeError) {
        switch outcome {
        case .waitingForDependencies:
            guard position == nil, !missing.isEmpty, reason == nil, recoveryHint == nil else {
                throw .invalidField("receipt.provisional")
            }
        case .accepted, .acceptedWithConflict:
            guard let position, position >= 1, missing.isEmpty, reason == nil, recoveryHint == nil else {
                throw .invalidField("receipt.final")
            }
        case .rejected:
            guard let position, position >= 1, missing.isEmpty, let reason, !reason.isEmpty,
                reason.utf8.count <= Self.maximumReasonBytes,
                reason.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || $0 == "_" })
            else { throw .invalidField("receipt.rejected") }
            if let recoveryHint {
                guard !recoveryHint.isEmpty, recoveryHint.utf8.count <= Self.maximumHintBytes else {
                    throw .invalidField("receipt.recoveryHint")
                }
            }
        }
        guard EnvelopeFields.isStrictlyAscending(missing) else { throw .invalidField("receipt.missing") }
        self.datasetID = datasetID
        self.epochID = epochID
        self.operationID = operationID
        self.digest = digest
        self.outcome = outcome
        self.position = position
        self.missing = missing
        self.reason = reason
        self.recoveryHint = recoveryHint
    }

    /// The canonical body Core signs.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            var fields: [(String, CanonicalValue)] = [
                ("datasetID", .string(datasetID.hex)), ("epochID", .string(epochID.hex)),
                ("operationID", .string(operationID.hex)), ("digest", .string(digest.hex)),
                ("outcome", .string(outcome.rawValue)),
            ]
            if let position { fields.append(("position", .integer(position))) }
            if !missing.isEmpty { fields.append(("missing", EnvelopeFields.identifierArray(missing))) }
            if let reason { fields.append(("reason", .string(reason))) }
            if let recoveryHint { fields.append(("recoveryHint", .string(recoveryHint))) }
            return try CanonicalEncoder.encode(
                .object(try CanonicalObject(fields)), limits: CanonicalLimits(maxBytes: Self.maximumBytes))
        } catch {
            throw .encoding(error)
        }
    }

    /// Decodes a body strictly: canonical JSON within 16 KiB, every field by its rules, no unknown fields.
    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> CoreReceipt {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: Self.maximumBytes)))
            guard let outcome = Outcome(rawValue: try reader.string("outcome")) else {
                throw OperationEnvelopeError.invalidField("receipt.outcome")
            }
            let position = try reader.optionalInteger("position")
            var missing: [Identifier128]?
            if let value = reader.optionalValue("missing") {
                guard case .array(let values) = value, !values.isEmpty else {
                    throw OperationEnvelopeError.invalidField("receipt.missing")
                }
                missing = try EnvelopeFields.sortedIdentifiers(values, "receipt.missing")
            }
            let receipt = try CoreReceipt(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "receipt.datasetID"),
                epochID: EnvelopeFields.identifier(reader.string("epochID"), "receipt.epochID"),
                operationID: EnvelopeFields.identifier(reader.string("operationID"), "receipt.operationID"),
                digest: EnvelopeFields.digest(reader.string("digest"), "receipt.digest"), outcome: outcome,
                position: position, missing: missing ?? [], reason: try reader.optionalString("reason"),
                recoveryHint: try reader.optionalString("recoveryHint"))
            try reader.finish()
            return receipt
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("receipt")
        }
    }
}

/// A Core receipt as it travels: its exact canonical body and Core's raw 64-byte signature.
public struct SignedCoreReceipt: Hashable, Sendable {
    public let body: [UInt8]
    public let signature: [UInt8]

    public init(body: [UInt8], signature: [UInt8]) throws(OperationEnvelopeError) {
        guard body.count <= CoreReceipt.maximumBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: CoreReceipt.maximumBytes))
        }
        guard signature.count == 64 else { throw .invalidField("receipt.signature") }
        self.body = body
        self.signature = signature
    }

    /// The receipt, decoded strictly; says nothing about who signed it.
    public func receipt() throws(OperationEnvelopeError) -> CoreReceipt { try CoreReceipt.decode(body: body) }

    /// The bytes a replica keeps for the receipt: the body followed by the signature.
    public var storedBytes: [UInt8] { body + signature }

    /// Splits bytes a replica kept back into the body and the signature.
    public init(storedBytes: [UInt8]) throws(OperationEnvelopeError) {
        guard storedBytes.count > 64 else { throw .invalidField("receipt.stored") }
        try self.init(body: Array(storedBytes.dropLast(64)), signature: Array(storedBytes.suffix(64)))
    }
}
