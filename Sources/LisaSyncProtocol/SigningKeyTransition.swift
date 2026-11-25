// Core's signing-key transition (plan §8.1.4, §8.5.3): the record that announces Core's next signing key. It names the
// previous and the next key and the activation position, the first commit position whose receipts the next key signs,
// and it is signed by both keys over the same canonical body, so it proves the public-key history K1→K2 and nothing
// more. Transitions chain: each names as its previous key the key the one before activated.

/// One transition in Core's signing-key history.
public struct SigningKeyTransition: Hashable, Sendable {
    public static let maximumBytes = 4_096

    public let datasetID: Identifier128
    /// 1 for the first transition, then one more each time.
    public let sequence: Int64
    /// Canonical SubjectPublicKeyInfo DER of the key being retired.
    public let previousKey: [UInt8]
    /// Canonical SubjectPublicKeyInfo DER of the key taking over.
    public let nextKey: [UInt8]
    /// The first commit position whose records the next key signs; the previous key's records end before it.
    public let activationPosition: Int64
    public let issuedAt: Int64

    public init(
        datasetID: Identifier128, sequence: Int64, previousKey: [UInt8], nextKey: [UInt8], activationPosition: Int64,
        issuedAt: Int64
    ) throws(OperationEnvelopeError) {
        guard sequence >= 1 else { throw .invalidField("transition.sequence") }
        guard activationPosition >= 1 else { throw .invalidField("transition.activationPosition") }
        guard (1...256).contains(previousKey.count), (1...256).contains(nextKey.count), previousKey != nextKey else {
            throw .invalidField("transition.keys")
        }
        self.datasetID = datasetID
        self.sequence = sequence
        self.previousKey = previousKey
        self.nextKey = nextKey
        self.activationPosition = activationPosition
        self.issuedAt = issuedAt
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)), ("sequence", .integer(sequence)),
                ("previousKey", .string(StrictBase64URL.encode(previousKey))),
                ("nextKey", .string(StrictBase64URL.encode(nextKey))),
                ("activationPosition", .integer(activationPosition)), ("issuedAt", .integer(issuedAt)),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> SigningKeyTransition {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            try SigningKeyTransition(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "transition.datasetID"),
                sequence: reader.integer("sequence"), previousKey: reader.bytes("previousKey"),
                nextKey: reader.bytes("nextKey"), activationPosition: reader.integer("activationPosition"),
                issuedAt: reader.integer("issuedAt"))
        }
    }
}

/// A transition as it travels: its exact body and both keys' raw signatures.
public struct SignedKeyTransition: Hashable, Sendable {
    public let body: [UInt8]
    /// By the previous key.
    public let previousSignature: [UInt8]
    /// By the next key.
    public let nextSignature: [UInt8]

    public init(body: [UInt8], previousSignature: [UInt8], nextSignature: [UInt8]) throws(OperationEnvelopeError) {
        guard !body.isEmpty, body.count <= SigningKeyTransition.maximumBytes else {
            throw .encoding(.tooLarge(bytes: body.count, limit: SigningKeyTransition.maximumBytes))
        }
        guard previousSignature.count == 64, nextSignature.count == 64 else {
            throw .invalidField("transition.signature")
        }
        self.body = body
        self.previousSignature = previousSignature
        self.nextSignature = nextSignature
    }

    /// The transition, decoded strictly; says nothing about who signed it.
    public func transition() throws(OperationEnvelopeError) -> SigningKeyTransition {
        try SigningKeyTransition.decode(body: body)
    }

    /// `{"body", "previousSignature", "nextSignature"}`, all base64url.
    public func canonicalValue() -> CanonicalValue {
        (try? CanonicalObject([
            ("body", .string(StrictBase64URL.encode(body))),
            ("previousSignature", .string(StrictBase64URL.encode(previousSignature))),
            ("nextSignature", .string(StrictBase64URL.encode(nextSignature))),
        ])).map(CanonicalValue.object) ?? .null
    }

    public static func decode(_ value: CanonicalValue) throws(OperationEnvelopeError) -> SignedKeyTransition {
        do {
            var reader = try CanonicalFieldReader(value)
            let signed = try SignedKeyTransition(
                body: reader.bytes("body"), previousSignature: reader.bytes("previousSignature"),
                nextSignature: reader.bytes("nextSignature"))
            try reader.finish()
            return signed
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("transition")
        }
    }
}

extension EnrollmentWire {
    /// `GET /v2/trust` once Core has rotated its signing key: `{"roster": …, "keyTransitions": [signed, …]}`, the
    /// transitions in sequence order. Without any, the body is `rosterBody`'s.
    public static func trustBody(_ roster: SignedRoster, transitions: [SignedKeyTransition])
        throws(OperationEnvelopeError) -> [UInt8]
    {
        guard !transitions.isEmpty else { return try rosterBody(roster) }
        return try EnrollmentCodec.encode(
            [
                ("roster", try roster.canonicalValue()),
                ("keyTransitions", .array(transitions.map { $0.canonicalValue() })),
            ],
            maximumBytes: SyncWire.maximumBodyBytes)
    }

    /// The roster and any transitions from a `GET /v2/trust` body.
    public static func trust(fromBody body: [UInt8]) throws(OperationEnvelopeError)
        -> (roster: SignedRoster, transitions: [SignedKeyTransition])
    {
        try EnrollmentCodec.decode(body, maximumBytes: SyncWire.maximumBodyBytes) { reader throws in
            let roster = try SignedRoster.decode(try reader.value("roster"))
            var transitions: [SignedKeyTransition] = []
            if let value = reader.optionalValue("keyTransitions") {
                guard case .array(let items) = value, !items.isEmpty, items.count <= 64 else {
                    throw OperationEnvelopeError.invalidField("keyTransitions")
                }
                for item in items { transitions.append(try SignedKeyTransition.decode(item)) }
            }
            return (roster: roster, transitions: transitions)
        }
    }
}
