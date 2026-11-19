// Device-token checks for the APNs request path: hexadecimal bytes, with no assumption about how many (S10).

import LisaRedaction

/// A device token in the form the request path `/3/device/<token>` needs: the token's bytes as hexadecimal digits.
/// Apple advises not to assume a token size, so only the format is checked, plus a generous bound on input length.
public struct APNsDeviceToken: Hashable, Sendable, CustomStringConvertible {
    /// The most hexadecimal digits accepted: an input bound far above today's tokens, not an expected size.
    public static let maxHexDigits = 1_024

    /// The token as lowercase hexadecimal digits.
    public let hex: Sensitive<String>

    /// Accepts a non-empty, even number of ASCII hexadecimal digits in either case. Anything else, including
    /// whitespace and non-ASCII digit forms, is malformed.
    public init?(_ text: String) {
        let bytes = text.utf8
        guard !bytes.isEmpty, bytes.count <= Self.maxHexDigits, bytes.count.isMultiple(of: 2),
            bytes.allSatisfy(Self.isASCIIHexDigit)
        else { return nil }
        hex = Sensitive(text.lowercased())
    }

    public var description: String { "<redacted APNs device token>" }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
}
