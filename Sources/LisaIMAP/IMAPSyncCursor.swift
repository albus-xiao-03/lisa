// Lisa's position in a mailbox folder, persisted as a versioned string: the folder's UIDVALIDITY, the highest UID
// fully handled, and the folder it belongs to (MAIL-02).

/// A mailbox position. A folder name, its UIDVALIDITY and a UID together name one immutable message
/// (RFC 9051 §2.3.1.1), so when UIDVALIDITY changes every stored UID is meaningless and the folder is read again.
struct IMAPSyncCursor: Hashable, Sendable {
    static let prefix = "imap-v1:"
    static let maxEncodedLength = 1_024
    let uidValidity: UInt32
    /// Every message with a UID up to this one was delivered in a batch or reported as skipped; 0 before the first.
    let lastUID: UInt32
    let folder: String

    init(uidValidity: UInt32, lastUID: UInt32, folder: String) {
        self.uidValidity = uidValidity
        self.lastUID = lastUID
        self.folder = folder
    }

    /// `imap-v1:<uidvalidity>:<last uid>:<folder>`, with the folder percent-encoded.
    var encoded: String { "\(Self.prefix)\(uidValidity):\(lastUID):\(Self.percentEncoded(folder))" }

    /// A cursor this version wrote, or nil for anything else.
    static func parse(_ text: String) -> IMAPSyncCursor? {
        guard text.utf8.count <= maxEncodedLength, text.hasPrefix(prefix) else { return nil }
        let fields = text.dropFirst(prefix.count).split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3, let validity = number(fields[0]), validity > 0, let last = number(fields[1]),
            let folder = percentDecoded(fields[2]), !folder.isEmpty
        else { return nil }
        return IMAPSyncCursor(uidValidity: validity, lastUID: last, folder: folder)
    }

    private static func number(_ text: Substring) -> UInt32? {
        guard !text.isEmpty, text.utf8.count <= 10, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return UInt32(text)
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2D
            || byte == 0x2E || byte == 0x5F || byte == 0x7E
    }

    private static func percentEncoded(_ text: String) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var bytes: [UInt8] = []
        for byte in text.utf8 {
            if isUnreserved(byte) {
                bytes.append(byte)
            } else {
                bytes += [0x25, hex[Int(byte >> 4)], hex[Int(byte & 0x0F)]]
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Decodes only the canonical form `percentEncoded` writes, so one folder has exactly one cursor spelling.
    private static func percentDecoded(_ text: Substring) -> String? {
        var bytes: [UInt8] = []
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte != 0x25 {
                guard isUnreserved(byte) else { return nil }
                bytes.append(byte)
                continue
            }
            guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else {
                return nil
            }
            bytes.append(high << 4 | low)
        }
        let decoded = String(decoding: bytes, as: UTF8.self)
        return percentEncoded(decoded) == String(text) ? decoded : nil
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        default: nil
        }
    }
}
