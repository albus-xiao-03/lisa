// The envelope addresses the SMTP transport submits: ASCII `local@domain` mailboxes with a dot-atom local part and a
// host-name domain, whose lowercased domain is also the name Lisa announces with EHLO.

/// An ASCII mailbox (RFC 5321 §4.1.2, restricted to a Dot-string local part and a host-name domain). Quoted local
/// parts, address literals and internationalized addresses, which need SMTPUTF8, are refused rather than rewritten.
struct SMTPMailbox: Hashable, Sendable {
    /// The address exactly as given; the transport never rewrites where mail goes.
    let address: String
    /// The domain, lowercased.
    let domain: String

    /// RFC 5321 §4.5.3.1: a local part of at most 64 octets, and a path (the address in angle brackets) of at most
    /// 256 octets.
    static let maxLocalPartBytes = 64
    static let maxAddressBytes = 254

    init?(_ text: String) {
        guard text.utf8.count <= Self.maxAddressBytes else { return nil }
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].utf8.count <= Self.maxLocalPartBytes, Self.isDotAtomText(parts[0]),
            Self.isHostName(parts[1])
        else { return nil }
        address = text
        domain = parts[1].lowercased()
    }

    /// RFC 5322 §3.2.3 `dot-atom-text`: atoms of `atext` joined by single dots.
    static func isDotAtomText(_ text: Substring) -> Bool {
        let specials = Set("!#$%&'*+-/=?^_`{|}~".utf8)
        return !text.isEmpty
            && text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { atom in
                !atom.isEmpty
                    && atom.utf8.allSatisfy { byte in
                        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                            || specials.contains(byte)
                    }
            }
    }

    /// A host name of letters, digits and hyphens in dot-separated labels, without a trailing dot, whose last label is
    /// not all digits. This is also exactly what LisaCurl accepts as an EHLO name.
    static func isHostName(_ text: Substring) -> Bool {
        guard !text.isEmpty, text.utf8.count <= 253 else { return false }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        let wellFormed = labels.allSatisfy { label in
            (1...63).contains(label.utf8.count) && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { byte in
                    (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
                        || byte == 0x2D
                }
        }
        return wellFormed && !(labels.last?.utf8.allSatisfy { (0x30...0x39).contains($0) } ?? true)
    }
}
