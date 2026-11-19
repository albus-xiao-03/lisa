// JSON5 quoted strings, unquoted keys and bare words: escapes, \u surrogate pairs and line continuations.

extension JSON5Scanner {
    /// Reads a single- or double-quoted string that starts at the current quote, and returns its decoded text.
    mutating func scanString(maxBytes: Int) throws(JSON5Error) -> String {
        let start = position
        guard let quote = current, quote == "\"" || quote == "'" else {
            throw error("expected text in quotes")
        }
        advance()
        var text = String.UnicodeScalarView()
        var byteCount = 0
        while true {
            guard let scalar = current else {
                throw error("this text is not closed; end it with the quote it starts with", at: start)
            }
            let decoded: Unicode.Scalar?
            if scalar == quote {
                advance()
                return String(text)
            } else if scalar == "\\" {
                decoded = try scanEscape(stringStart: start)
            } else if scalar == "\n" || scalar == "\r" {
                throw error("text in quotes cannot run onto the next line; write \\n, or end the line with \\")
            } else {
                advance()
                decoded = scalar
            }
            if let decoded {
                byteCount += UTF8.width(decoded)
                guard byteCount <= maxBytes else {
                    throw error("this text is longer than \(maxBytes) bytes", at: start)
                }
                text.append(decoded)
            }
        }
    }

    /// Reads one escape sequence after a backslash. Returns `nil` for a line continuation, which adds nothing.
    private mutating func scanEscape(stringStart: SourcePosition) throws(JSON5Error) -> Unicode.Scalar? {
        let start = position
        advance()
        guard let scalar = current else {
            throw error("this text is not closed; end it with the quote it starts with", at: stringStart)
        }
        if let simple = Self.singleCharacterEscape(scalar) {
            advance()
            return simple
        }
        switch scalar {
        case "0":
            advance()
            if let next = current, Self.isDecimalDigit(next) {
                throw error("octal escapes are not allowed; write \\u followed by four hexadecimal digits", at: start)
            }
            return "\u{0}"
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            throw error("\\1 to \\9 are not escapes; write \\u followed by four hexadecimal digits", at: start)
        case "x":
            advance()
            let value = try scanHexDigits(2, escapeStart: start)
            return Unicode.Scalar(UInt8(value))
        case "u":
            advance()
            return try scanUnicodeEscape(escapeStart: start)
        case "\n", "\u{2028}", "\u{2029}":
            advance()
            return nil
        case "\r":
            advance()
            if current == "\n" {
                advance()
            }
            return nil
        default:
            // Any other escaped character stands for itself, as in \' and \".
            advance()
            return scalar
        }
    }

    private static func singleCharacterEscape(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar {
        case "b": "\u{08}"
        case "f": "\u{0C}"
        case "n": "\n"
        case "r": "\r"
        case "t": "\t"
        case "v": "\u{0B}"
        default: nil
        }
    }

    private mutating func scanHexDigits(_ count: Int, escapeStart: SourcePosition) throws(JSON5Error) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<count {
            guard let scalar = current, let digit = Self.hexValue(scalar) else {
                throw error("this escape needs \(count) hexadecimal digits (0-9, a-f)", at: escapeStart)
            }
            value = value << 4 | digit
            advance()
        }
        return value
    }

    /// Reads the four hexadecimal digits after `\u`, joining a UTF-16 surrogate pair written as two escapes.
    private mutating func scanUnicodeEscape(escapeStart: SourcePosition) throws(JSON5Error) -> Unicode.Scalar {
        let first = try scanHexDigits(4, escapeStart: escapeStart)
        switch first {
        case 0xD800...0xDBFF:
            guard current == "\\", peek() == "u" else {
                throw error(
                    "this \\u escape is the first half of a surrogate pair; follow it with \\uDC00 to \\uDFFF",
                    at: escapeStart)
            }
            advance()
            advance()
            let second = try scanHexDigits(4, escapeStart: escapeStart)
            guard (0xDC00...0xDFFF).contains(second),
                let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
            else {
                throw error(
                    "this surrogate pair is incomplete; its second half must be \\uDC00 to \\uDFFF", at: escapeStart)
            }
            return scalar
        default:
            guard let scalar = Unicode.Scalar(first) else {
                throw error(
                    "this \\u escape is the second half of a surrogate pair without its first half", at: escapeStart)
            }
            return scalar
        }
    }

    /// Reads an unquoted key: an ECMAScript 5.1 identifier name, with `\u` escapes decoded.
    mutating func scanIdentifierName(maxBytes: Int) throws(JSON5Error) -> String {
        let start = position
        var name = String.UnicodeScalarView()
        var byteCount = 0
        while let scalar = current {
            let decoded: Unicode.Scalar
            if scalar == "\\" {
                let escapeStart = position
                advance()
                guard current == "u" else {
                    throw error("only \\u escapes are allowed in an unquoted key", at: escapeStart)
                }
                advance()
                decoded = try scanUnicodeEscape(escapeStart: escapeStart)
                guard name.isEmpty ? Self.isIdentifierStart(decoded) : Self.isIdentifierPart(decoded) else {
                    throw error(
                        "this escape produces a character that an unquoted key cannot contain; put the key in quotes",
                        at: escapeStart)
                }
            } else if name.isEmpty ? Self.isIdentifierStart(scalar) : Self.isIdentifierPart(scalar) {
                advance()
                decoded = scalar
            } else {
                break
            }
            byteCount += UTF8.width(decoded)
            guard byteCount <= maxBytes else {
                throw error("this key is longer than \(maxBytes) bytes", at: start)
            }
            name.append(decoded)
        }
        guard !name.isEmpty else {
            throw error("expected a key: a name such as timeZone, or text in quotes", at: start)
        }
        return String(name)
    }

    /// Reads a bare word made of identifier characters, such as `true`, `null` or `Infinity`.
    mutating func scanWord() -> String {
        var word = String.UnicodeScalarView()
        while let scalar = current, word.isEmpty ? Self.isIdentifierStart(scalar) : Self.isIdentifierPart(scalar) {
            word.append(scalar)
            advance()
        }
        return String(word)
    }
}
