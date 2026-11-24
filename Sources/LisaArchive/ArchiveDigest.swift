// SHA-256 as the archive codec uses it: key IDs, the header digest and the signed digest pair (plan §8.6.6).

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// SHA-256 over byte arrays for the archive codec.
enum ArchiveDigest {
    static func sha256(_ bytes: [UInt8]) -> [UInt8] { [UInt8](Digests.sha256(Data(bytes))) }

    /// A key ID: the SHA-256 of a public key's canonical DER, like `P256Verifier.fingerprint`.
    static func keyID(ofSPKI spki: [UInt8]) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: sha256(spki))
    }
}
