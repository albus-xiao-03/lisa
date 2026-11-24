// The hello's wire form (plan §8.7 "Hello", §8.16.1 encoding): canonical JSON carried in a hello frame.

import LisaSyncProtocol

extension NearbyHello {
    /// A hello body is at most 4 KiB.
    public static let wireLimits = CanonicalLimits(maxBytes: 4_096)

    /// The canonical JSON body: `protocolVersion`, `deviceID`, `rosterEpoch`, `rosterVersion`, `head` (lowercase
    /// hexadecimal) and `nonce` (strict base64url).
    public func canonicalBody() throws(TrustError) -> [UInt8] {
        do {
            let object = try CanonicalObject([
                ("protocolVersion", .integer(Self.protocolVersion)), ("deviceID", .string(deviceID.hex)),
                ("rosterEpoch", .string(rosterEpoch.hex)), ("rosterVersion", .integer(rosterVersion)),
                ("head", .string(head.hex)), ("nonce", .string(StrictBase64URL.encode(nonce))),
            ])
            return try CanonicalEncoder.encode(.object(object), limits: Self.wireLimits)
        } catch {
            throw .invalidNearbyValue("hello")
        }
    }

    /// Decodes a peer's hello strictly: canonical JSON within the limit, this protocol version, every field valid and
    /// no unknown field.
    public init(canonicalBody bytes: [UInt8]) throws(TrustError) {
        self = try Self.decodeBody(bytes)
    }

    private static func decodeBody(_ bytes: [UInt8]) throws(TrustError) -> NearbyHello {
        do {
            var reader = try CanonicalFieldReader(try CanonicalDecoder.decode(bytes, limits: wireLimits))
            guard try reader.integer("protocolVersion") == protocolVersion else {
                throw TrustError.invalidNearbyValue("protocolVersion")
            }
            let hello = try NearbyHello(
                deviceID: try Identifier128(hex: try reader.string("deviceID")),
                rosterEpoch: try Identifier128(hex: try reader.string("rosterEpoch")),
                rosterVersion: try reader.integer("rosterVersion"), head: try Digest256(hex: try reader.string("head")),
                nonce: try reader.bytes("nonce"))
            try reader.finish()
            return hello
        } catch let error as TrustError {
            throw error
        } catch {
            throw .invalidNearbyValue("hello")
        }
    }
}
