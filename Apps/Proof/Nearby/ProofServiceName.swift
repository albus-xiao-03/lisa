// PROOF ONLY — Apps/Proof never ships. Random Bonjour instance names (plan §8.7: random names, nothing identifying),
// drawn fresh for every listener.

import LisaCrypto

enum ProofServiceName {
    static func random() -> String {
        "lisa-" + LowercaseHexText.encode(Array(RandomTokens.bytes(6)))
    }
}
