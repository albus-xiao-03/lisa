// The derived identities of Core-signed legacy children (plan §8.12.2): pure functions of the original request.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Child IDs and the child-set digest of an R1 request's conversion.
///
/// - Child ID: the first 16 bytes of `SHA-256("lisa-v1-child-v1" ‖ 0x00 ‖ len32(dataset) ‖ dataset ‖ len32(scope) ‖
///   scope ‖ len32(requestID) ‖ requestID ‖ len32(discriminator) ‖ discriminator)`, where `len32` is a big-endian
///   32-bit length, the dataset is its 16 raw bytes and the strings are UTF-8.
/// - Set digest: SHA-256 of the ordered child IDs' raw bytes, concatenated.
///
/// - Incarnation: the children's origin, derived from the dataset, scope and request ID; see `incarnationID`.
///
/// Every holder can recompute these, so every legitimate copy of a child has the same ID in any epoch.
public enum LegacyChildIdentity {
    static let label = Array("lisa-v1-child-v1".utf8)

    public static func childID(dataset: Identifier128, scope: String, requestID: String, discriminator: String)
        -> Identifier128
    {
        var input = label + [0x00]
        for part in [dataset.bytes, Array(scope.utf8), Array(requestID.utf8), Array(discriminator.utf8)] {
            input += length32(part.count) + part
        }
        let digest = [UInt8](Digests.sha256(Data(input)))
        // The first 16 bytes of a 32-byte digest.
        return try! Identifier128(bytes: Array(digest.prefix(16)))
    }

    /// The incarnation of a request's children: the first 16 bytes of `SHA-256("lisa-v1-incarnation-v1" ‖
    /// len32(dataset) ‖ dataset ‖ len32(scope) ‖ scope ‖ len32(requestID) ‖ requestID)` (plan §8.12.2; unlike the child
    /// ID, no 0x00 follows the label). Each child's sequence is its index plus one.
    public static func incarnationID(dataset: Identifier128, scope: String, requestID: String) -> Identifier128 {
        var input = incarnationLabel
        for part in [dataset.bytes, Array(scope.utf8), Array(requestID.utf8)] { input += length32(part.count) + part }
        let digest = [UInt8](Digests.sha256(Data(input)))
        // The first 16 bytes of a 32-byte digest.
        return try! Identifier128(bytes: Array(digest.prefix(16)))
    }

    static let incarnationLabel = Array("lisa-v1-incarnation-v1".utf8)

    public static func setDigest(orderedChildIDs: [Identifier128]) -> Digest256 {
        OperationDigest.of(body: orderedChildIDs.flatMap(\.bytes))
    }

    static func length32(_ count: Int) -> [UInt8] {
        let value = UInt32(count)
        return [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}
