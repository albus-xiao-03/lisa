// An API request's target on the wire: path segments and query items percent-encoded with RFC 3986's unreserved
// characters only, query items sorted by name. Network clients build URLs from it; the server decodes it strictly, and
// `+` is never a space.

extension APIRequest {
    /// The origin-form target, for example `/v1/tasks?cursor=a%2Bb&limit=5`. `nil` when the path is not usable: it
    /// must start with `/`, and no segment may be empty, `.` or `..`, or contain `?`, `#` or a control character.
    public func encodedTarget() -> String? {
        guard path.hasPrefix("/") else { return nil }
        var target = ""
        for segment in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            guard !segment.isEmpty, segment != ".", segment != "..",
                !segment.unicodeScalars.contains(where: { $0 == "?" || $0 == "#" || Self.isControl($0) })
            else { return nil }
            target += "/" + Self.percentEncoded(segment)
        }
        guard !target.isEmpty else { return nil }
        if !query.isEmpty {
            let items = query.sorted { $0.key < $1.key }.map {
                Self.percentEncoded($0.key[...]) + "=" + Self.percentEncoded($0.value[...])
            }
            target += "?" + items.joined(separator: "&")
        }
        return target
    }

    /// `text` with every byte outside ALPHA, DIGIT, `-`, `.`, `_` and `~` written as `%XX`.
    static func percentEncoded(_ text: Substring) -> String {
        var encoded = ""
        for byte in text.utf8 {
            if isUnreserved(byte) {
                encoded.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                encoded += byte < 16 ? "%0" + hex : "%" + hex
            }
        }
        return encoded
    }

    static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"),
            UInt8(ascii: "~"):
            true
        default:
            false
        }
    }

    static func isControl(_ scalar: Unicode.Scalar) -> Bool { scalar.value < 0x20 || scalar.value == 0x7F }
}
