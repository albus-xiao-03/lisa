// Cleans an optional item title before it goes into a payload: no control, separator or bidirectional-control
// characters, single spaces, and a bound on input size.

/// Title cleaning for payloads. Titles can come from forwarded mail, so they are treated as untrusted text.
enum APNsTitleText {
    /// The most UTF-8 bytes of a title considered at all; the payload limit is smaller still.
    static let maxInputBytes = 4_096

    /// The title with each disallowed character or run of whitespace replaced by one space and surrounding spaces
    /// removed, considering at most ``maxInputBytes`` bytes; nil when nothing is left.
    static func cleaned(_ title: String) -> String? {
        var scalars = String.UnicodeScalarView()
        var consumed = 0
        var pendingSpace = false
        for scalar in title.unicodeScalars {
            consumed += UTF8.width(scalar)
            if consumed > maxInputBytes { break }
            if isDisallowed(scalar) || scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        return scalars.isEmpty ? nil : String(scalars)
    }

    /// Controls, line and paragraph separators, and the bidirectional formatting controls that can make displayed
    /// text read differently from its content. Other format characters, such as the zero-width joiner in emoji
    /// sequences, are kept.
    static func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator, .surrogate:
            return true
        case .format:
            return [0x061C, 0x200E, 0x200F].contains(scalar.value) || (0x202A...0x202E).contains(scalar.value)
                || (0x2066...0x2069).contains(scalar.value)
        default:
            return false
        }
    }
}
