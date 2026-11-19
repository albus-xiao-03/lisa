// A folder name Lisa can send in a command, and its quoted form (RFC 9051 §4.3, §5.1).

/// A folder name of 1 to 255 printable ASCII characters. Non-ASCII names would need modified UTF-7 on IMAP4rev1
/// servers (RFC 3501 §5.1.3), so they are refused instead of being sent in a form the server may misread.
struct IMAPMailboxName: Hashable, Sendable {
    static let maxBytes = 255
    let name: String

    init?(_ name: String) {
        guard !name.isEmpty, name.utf8.count <= Self.maxBytes, name.utf8.allSatisfy({ (0x20...0x7E).contains($0) })
        else { return nil }
        self.name = name
    }

    /// The name as a quoted string, with `\` and `"` escaped.
    var quoted: String {
        var bytes: [UInt8] = [0x22]
        for byte in name.utf8 {
            if byte == 0x22 || byte == 0x5C { bytes.append(0x5C) }
            bytes.append(byte)
        }
        bytes.append(0x22)
        return String(decoding: bytes, as: UTF8.self)
    }
}
