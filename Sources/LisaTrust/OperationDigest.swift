// The digest of an operation: SHA-256 over the complete canonical signed body (plan §8.2.1).

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Computes operation digests. The signature is not part of the digest, so a re-signed copy (for example after a
/// key rotation) keeps its digest, and every legitimate copy of a legacy child has the same one (§8.12.2).
public enum OperationDigest {
    public static func of(body: [UInt8]) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: [UInt8](Digests.sha256(Data(body))))
    }

    public static func of(_ operation: SignedOperation) -> Digest256 {
        of(body: operation.body)
    }
}
