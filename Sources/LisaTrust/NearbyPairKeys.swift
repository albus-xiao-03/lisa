// Design A's pair-specific pre-shared keys, rotating discovery tags and rejoin identities (plan §8.7).

import LisaCrypto
import LisaSyncProtocol

/// The derivations of Design A. Both devices of a pair compute the same values.
///
/// - Pair key: `K_ij = HKDF-SHA256(ECDH(i, j), salt: dataset ID, info: "lisa-nearby-psk-v1" ‖ lower ID ‖ higher ID)`,
///   32 bytes, with the 16-byte device IDs ordered bytewise.
/// - Window: the Unix time in seconds divided by 900 (15 minutes), as 8 bytes big-endian.
/// - Discovery tag: the first 16 bytes of `HMAC-SHA256(discovery secret, "lisa-disc-v1" ‖ window ‖ device ID)`.
/// - Rejoin identity: the first 16 bytes of `HMAC-SHA256(K_ij, "lisa-rejoin-v1" ‖ window)`.
public enum NearbyPairKeys {
    public static let windowSeconds: Int64 = 900
    public static let tagLength = 16
    static let pskLabel = Array("lisa-nearby-psk-v1".utf8)
    static let discoveryLabel = Array("lisa-disc-v1".utf8)
    static let rejoinLabel = Array("lisa-rejoin-v1".utf8)

    /// The 32-byte pre-shared key of this device and `peerDevice`.
    public static func pairKey(
        ownKey: P256AgreementKey, peerKey: P256AgreementPublicKey, dataset: Identifier128, ownDevice: Identifier128,
        peerDevice: Identifier128
    ) throws(CryptoKeyError) -> [UInt8] {
        let ordered = [ownDevice.bytes, peerDevice.bytes].sorted { $0.lexicographicallyPrecedes($1) }
        return try ownKey.derivedKey(
            with: peerKey, salt: dataset.bytes, info: pskLabel + ordered[0] + ordered[1], outputByteCount: 32)
    }

    /// The discovery window containing a Unix time in seconds.
    public static func window(atUnixSeconds seconds: Int64) -> UInt64 {
        UInt64(max(0, seconds) / windowSeconds)
    }

    /// The tag a listener publishes for `device` in `window`.
    public static func discoveryTag(secret: [UInt8], window: UInt64, device: Identifier128) -> [UInt8] {
        Array(
            HMACSHA256.authenticationCode(for: discoveryLabel + bigEndian(window) + device.bytes, key: secret)
                .prefix(tagLength))
    }

    /// The PSK identity a rejoining device sends to one candidate peer in `window`.
    public static func rejoinIdentity(pairKey: [UInt8], window: UInt64) -> [UInt8] {
        Array(HMACSHA256.authenticationCode(for: rejoinLabel + bigEndian(window), key: pairKey).prefix(tagLength))
    }

    static func bigEndian(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> (56 - 8 * $0)) }
    }
}
