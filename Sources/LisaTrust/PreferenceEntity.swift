// The entity a preference key names (docs/DECISIONS.md D-73). A preference is a register per key, so every device,
// Core and every epoch name the same key by the same ID, derived from the key alone; R1's random record IDs, which a
// delete and a later set change, play no part.

import Foundation
import LisaCrypto
import LisaSyncProtocol

public enum PreferenceEntity {
    /// The entity type of preference operations.
    public static let entityType = "preference"

    /// The first 16 bytes of `SHA-256("lisa-preference-key-v1" ‖ 0x00 ‖ key)`.
    public static func id(forKey key: String) -> Identifier128 {
        var bytes = Array("lisa-preference-key-v1".utf8)
        bytes.append(0)
        bytes += Array(key.utf8)
        // A SHA-256 value is always 32 bytes, so its first 16 make an identifier.
        return try! Identifier128(bytes: Array(Digests.sha256(Data(bytes)).prefix(16)))
    }
}
