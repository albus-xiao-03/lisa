// Answering and checking challenges (plan §8.1.5). The signed message is fixed by the plan:
// `"lisa-challenge-v1" ‖ 0x00 ‖ purpose ‖ datasetID ‖ epochID ‖ challengeID ‖ nonce ‖ deviceID ‖ keyID ‖ SHA-256(body)`,
// with the purpose as its ASCII token, identifiers as their 16 raw bytes, the 32-byte nonce, the key ID as SHA-256 of
// the operation key's SubjectPublicKeyInfo DER, and the SHA-256 of the exact body the challenge authorizes. Every
// field after the purpose has a fixed length, and the purposes are distinct tokens, so two messages are equal only
// when every field is.

import Foundation
import LisaCrypto
import LisaSyncProtocol

/// Signs and checks challenge responses.
public enum ChallengeSigning {
    static let label = Array("lisa-challenge-v1".utf8)

    /// The key ID a proof names: SHA-256 of the key's SubjectPublicKeyInfo DER.
    public static func keyID(_ key: P256Verifier) -> Digest256 {
        // A SHA-256 value is always 32 bytes.
        try! Digest256(bytes: key.fingerprint)
    }

    /// The exact message the device signs.
    public static func message(for challenge: Challenge, keyID: Digest256, body: [UInt8]) -> [UInt8] {
        label + [0x00] + Array(challenge.purpose.rawValue.utf8) + challenge.datasetID.bytes + challenge.epochID.bytes
            + challenge.challengeID.bytes + challenge.nonce + challenge.deviceID.bytes + keyID.bytes
            + [UInt8](Digests.sha256(Data(body)))
    }

    /// The device's proof for `body`, signed by its operation key.
    public static func respond(to challenge: Challenge, body: [UInt8], with operationKey: some MessageSigning) throws
        -> ChallengeProof
    {
        let keyID = keyID(operationKey.verifier)
        let signature = try operationKey.rawSignature(for: message(for: challenge, keyID: keyID, body: body))
        return try ChallengeProof(challengeID: challenge.challengeID, keyID: keyID, signature: signature)
    }

    /// Whether `proof` is `key`'s signature for this challenge and exactly this body.
    public static func isValid(_ proof: ChallengeProof, for challenge: Challenge, body: [UInt8], key: P256Verifier)
        -> Bool
    {
        proof.challengeID == challenge.challengeID && proof.keyID == keyID(key)
            && key.isValidSignature(proof.signature, for: message(for: challenge, keyID: proof.keyID, body: body))
    }
}
