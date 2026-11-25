// A device's operation-key rotation (plan §8.1.4 "device key rotation"): the device names its current and its next
// operation key in a record signed by both, and Core replaces the key in its registry and signs a new roster that
// keeps the previous key in the device's history. It travels as `{"update": {"body", "previousSignature",
// "nextSignature"}}` to `POST /v2/devices/current/key-update`, with the device's bearer credential.

/// What a device signs to rotate its operation key.
public struct DeviceKeyUpdate: Hashable, Sendable {
    public static let maximumBytes = 4_096

    public let datasetID: Identifier128
    public let deviceID: Identifier128
    /// Canonical SubjectPublicKeyInfo DER of the key being retired.
    public let previousKey: [UInt8]
    /// Canonical SubjectPublicKeyInfo DER of the key taking over.
    public let nextKey: [UInt8]
    public let createdAt: Int64

    public init(
        datasetID: Identifier128, deviceID: Identifier128, previousKey: [UInt8], nextKey: [UInt8], createdAt: Int64
    ) throws(OperationEnvelopeError) {
        guard (1...256).contains(previousKey.count), (1...256).contains(nextKey.count), previousKey != nextKey else {
            throw .invalidField("keyUpdate.keys")
        }
        self.datasetID = datasetID
        self.deviceID = deviceID
        self.previousKey = previousKey
        self.nextKey = nextKey
        self.createdAt = createdAt
    }

    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode(
            [
                ("datasetID", .string(datasetID.hex)), ("deviceID", .string(deviceID.hex)),
                ("previousKey", .string(StrictBase64URL.encode(previousKey))),
                ("nextKey", .string(StrictBase64URL.encode(nextKey))), ("createdAt", .integer(createdAt)),
            ], maximumBytes: Self.maximumBytes)
    }

    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> DeviceKeyUpdate {
        try EnrollmentCodec.decode(body, maximumBytes: maximumBytes) { reader throws in
            try DeviceKeyUpdate(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "keyUpdate.datasetID"),
                deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "keyUpdate.deviceID"),
                previousKey: reader.bytes("previousKey"), nextKey: reader.bytes("nextKey"),
                createdAt: reader.integer("createdAt"))
        }
    }

    /// The body of `POST /v2/devices/current/key-update`.
    public static func requestBody(_ signed: SignedKeyTransition) throws(OperationEnvelopeError) -> [UInt8] {
        try EnrollmentCodec.encode([("update", signed.canonicalValue())], maximumBytes: 2 * maximumBytes)
    }

    /// The signed update from that body: the same two-signature form as a key transition.
    public static func request(fromBody body: [UInt8]) throws(OperationEnvelopeError) -> SignedKeyTransition {
        try EnrollmentCodec.decode(body, maximumBytes: 2 * maximumBytes) { reader throws in
            try SignedKeyTransition.decode(try reader.value("update"))
        }
    }
}
