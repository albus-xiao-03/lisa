// The decision key and token of an administrative hold (plan §8.12.2 "Each decision is bound to one hold"; docs/
// DECISIONS.md D-75). Both are derived from durable state, so the same hold always shows the same token, also after a
// restart.
//
// - Decision key: `SHA-256("lisa-legacy-decision-v1" ‖ 0x00 ‖ dataset ‖ 0x00 ‖ scope ‖ 0x00 ‖ requestID ‖ 0x00 ‖
//   childID ‖ 0x00 ‖ holdGeneration)`. The dataset and child ID are their 16 raw bytes, the scope and request ID UTF-8,
//   and the generation its decimal digits in ASCII. Fixed lengths and text without NUL keep the parts apart.
// - Token: `LR-` and the key in base32 (RFC 4648's alphabet, upper case, no padding), 52 characters in full. It is
//   shown at 8 characters (40 bits), longer in steps of 4 (20 bits) until it is unique among every hold Core issued.

import Foundation
import LisaCrypto
import LisaSyncProtocol

public enum LegacyDecisionToken {
    public static let prefix = "LR-"
    /// The shortest token: 40 bits.
    public static let minimumCharacters = 8
    /// What a longer token adds at a time: 20 bits.
    public static let stepCharacters = 4

    static let label = Array("lisa-legacy-decision-v1".utf8)
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// The decision key of hold generation `holdGeneration` of the child `childID`.
    public static func decisionKey(
        dataset: Identifier128, scope: String, requestID: String, childID: Identifier128, holdGeneration: Int64
    ) -> Digest256 {
        var input = label
        for part in [dataset.bytes, Array(scope.utf8), Array(requestID.utf8), childID.bytes] {
            input += [0x00] + part
        }
        input += [0x00] + Array(String(holdGeneration).utf8)
        // A SHA-256 value is always 32 bytes.
        return try! Digest256(bytes: [UInt8](Digests.sha256(Data(input))))
    }

    /// The whole key in base32: 52 characters, the last carrying one bit.
    public static func encoded(_ key: Digest256) -> String {
        var text = ""
        var buffer = 0
        var bits = 0
        for byte in key.bytes {
            buffer = buffer << 8 | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                text.append(alphabet[buffer >> bits & 0x1F])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { text.append(alphabet[buffer << (5 - bits) & 0x1F]) }
        return text
    }

    /// The token of `key` shown at `characters` characters of its base32 form.
    public static func token(_ key: Digest256, characters: Int = minimumCharacters) -> String {
        prefix + String(encoded(key).prefix(characters))
    }

    /// The base32 prefix a typed token names, in upper case; `nil` unless it is `LR-` followed by at least 8 and at
    /// most 52 base32 characters. Lower case is accepted; nothing else is mapped.
    public static func typedPrefix(_ token: String) -> String? {
        guard token.uppercased().hasPrefix(prefix) else { return nil }
        let rest = token.dropFirst(prefix.count).uppercased()
        guard (minimumCharacters...52).contains(rest.count), rest.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return String(rest)
    }
}
