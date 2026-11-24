// PROOF ONLY — Apps/Proof never ships. Lowercase hexadecimal for observations and evidence (LisaSyncProtocol's
// own encoder is internal to that module).

enum LowercaseHexText {
    static func encode(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }
}
