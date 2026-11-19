// The JSON5 character cursor: line and column tracking, whitespace, comments and character classes.

/// Walks a document's Unicode scalars and tracks the 1-based line and column of the current scalar.
struct JSON5Scanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    /// The position of the current scalar.
    private(set) var position = SourcePosition(line: 1, column: 1)

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    /// The current scalar, or `nil` at the end of the document.
    var current: Unicode.Scalar? {
        index < scalars.count ? scalars[index] : nil
    }

    /// The scalar `offset` places after the current one.
    func peek(_ offset: Int = 1) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    var isAtEnd: Bool { index >= scalars.count }

    /// Moves past the current scalar. LF, CR, CR LF, U+2028 and U+2029 each end one line.
    mutating func advance() {
        guard let scalar = current else { return }
        index += 1
        switch scalar {
        case "\n", "\u{2028}", "\u{2029}":
            position = SourcePosition(line: position.line + 1, column: 1)
        case "\r" where current != "\n":
            position = SourcePosition(line: position.line + 1, column: 1)
        default:
            position.column += 1
        }
    }

    /// Skips whitespace, `//` line comments and `/* */` block comments.
    mutating func skipTrivia() throws(JSON5Error) {
        while let scalar = current {
            if Self.isWhitespace(scalar) {
                advance()
            } else if scalar == "/", peek() == "/" {
                while let next = current, !Self.isLineTerminator(next) {
                    advance()
                }
            } else if scalar == "/", peek() == "*" {
                try skipBlockComment()
            } else {
                return
            }
        }
    }

    private mutating func skipBlockComment() throws(JSON5Error) {
        let start = position
        advance()
        advance()
        while let scalar = current {
            if scalar == "*", peek() == "/" {
                advance()
                advance()
                return
            }
            advance()
        }
        throw error("this comment is not closed; end it with */", at: start)
    }

    /// A syntax error at `position`, or at the current position.
    func error(_ problem: String, at position: SourcePosition? = nil) -> JSON5Error {
        let location = position ?? self.position
        return .syntax(line: location.line, column: location.column, problem: problem)
    }

    // MARK: - Character classes (JSON5 and ECMAScript 5.1)

    static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\t", "\n", "\u{0B}", "\u{0C}", "\r", " ", "\u{A0}", "\u{2028}", "\u{2029}", "\u{FEFF}": true
        default: scalar.properties.generalCategory == .spaceSeparator
        }
    }

    static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}"
    }

    static func isDecimalDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    static func hexValue(_ scalar: Unicode.Scalar) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39: scalar.value - 0x30
        case 0x41...0x46: scalar.value - 0x41 + 10
        case 0x61...0x66: scalar.value - 0x61 + 10
        default: nil
        }
    }

    /// `$`, `_` or a Unicode letter (categories Lu, Ll, Lt, Lm, Lo and Nl).
    static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "$" || scalar == "_" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .letterNumber:
            return true
        default:
            return false
        }
    }

    /// An identifier start, a combining mark, a digit, connector punctuation, ZWNJ or ZWJ.
    static func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        if isIdentifierStart(scalar) || scalar == "\u{200C}" || scalar == "\u{200D}" { return true }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .decimalNumber, .connectorPunctuation:
            return true
        default:
            return false
        }
    }
}
