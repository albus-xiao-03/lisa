// The nearby session hello (plan §8.7).

import LisaSyncProtocol

/// What each side announces first: protocol version, device, roster (epoch and version), confirmed head and a fresh
/// 32-byte nonce.
public struct NearbyHello: Hashable, Sendable {
    public static let protocolVersion: Int64 = 1
    public static let nonceLength = 32

    public let deviceID: Identifier128
    public let rosterEpoch: Identifier128
    public let rosterVersion: Int64
    public let head: Digest256
    public let nonce: [UInt8]

    public init(
        deviceID: Identifier128, rosterEpoch: Identifier128, rosterVersion: Int64, head: Digest256, nonce: [UInt8]
    ) throws(TrustError) {
        guard nonce.count == Self.nonceLength else { throw .invalidNearbyValue("nonce") }
        self.deviceID = deviceID
        self.rosterEpoch = rosterEpoch
        self.rosterVersion = rosterVersion
        self.head = head
        self.nonce = nonce
    }
}
