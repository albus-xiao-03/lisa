// Reads the tokens of one framed IMAP response (RFC 9051 §4, §9): atoms, numbers, quoted strings, literals and
// parenthesized lists, with bounded nesting when a value is skipped.

import Foundation

/// A cursor over one response. Every read either succeeds or throws `IMAPProtocolError.malformedResponse`.
struct IMAPTokenReader {
    /// The deepest list nesting accepted when a value is skipped (BODYSTRUCTURE nests one level per MIME part).
    static let maxNesting = 64
    /// The longest keyword, capability or response-code name accepted.
    static let maxKeywordBytes = 1_024
    private let text: [UInt8]
    private let literals: [Data]
    private let literalEnds: [Int]
    private(set) var position = 0
    private var nextLiteral = 0

    init(_ response: IMAPRawResponse) {
        text = response.text
        literals = response.literals
        literalEnds = response.literalEnds
    }

    var isAtEnd: Bool { position >= text.count }

    func peek() -> UInt8? { position < text.count ? text[position] : nil }

    /// Consumes `byte` if it comes next.
    mutating func consume(_ byte: UInt8) -> Bool {
        guard peek() == byte else { return false }
        position += 1
        return true
    }

    mutating func expect(_ byte: UInt8, _ what: String) throws(IMAPProtocolError) {
        guard consume(byte) else { throw .malformedResponse("expected \(what)") }
    }

    mutating func expectSpace() throws(IMAPProtocolError) { try expect(0x20, "a space") }

    mutating func expectEnd(_ context: String) throws(IMAPProtocolError) {
        guard isAtEnd else { throw .malformedResponse("unexpected data after \(context)") }
    }

    /// One or more ATOM-CHARs (any CHAR except atom-specials), returned uppercased for keyword comparison. It stops
    /// at `[`, which starts a FETCH section (`BODY[...]`) or a response code.
    mutating func readKeyword() throws(IMAPProtocolError) -> String {
        let start = position
        while let byte = peek(), Self.isAtomChar(byte), byte != 0x5B { position += 1 }
        guard position > start else { throw .malformedResponse("expected an atom") }
        guard position - start <= Self.maxKeywordBytes else { throw .malformedResponse("an atom was too long") }
        return String(decoding: text[start..<position], as: UTF8.self).uppercased()
    }

    /// A tag: ASTRING-CHARs except `+` (RFC 9051 §9), returned as sent.
    mutating func readTag() throws(IMAPProtocolError) -> String {
        let start = position
        while let byte = peek(), Self.isAtomChar(byte) || byte == 0x5D, byte != 0x2B { position += 1 }
        guard position > start, position - start <= 64 else { throw .malformedResponse("expected a tag") }
        return String(decoding: text[start..<position], as: UTF8.self)
    }

    /// `number64` (RFC 9051 §9): an unsigned 63-bit decimal number.
    mutating func readNumber() throws(IMAPProtocolError) -> UInt64 {
        let start = position
        var value: UInt64 = 0
        while let byte = peek(), (0x30...0x39).contains(byte) {
            let digit = UInt64(byte - 0x30)
            guard value <= (UInt64(Int64.max) - digit) / 10 else { throw .malformedResponse("a number is too large") }
            value = value * 10 + digit
            position += 1
        }
        guard position > start else { throw .malformedResponse("expected a number") }
        return value
    }

    /// `number` (RFC 9051 §9): an unsigned 32-bit decimal number.
    mutating func readNumber32() throws(IMAPProtocolError) -> UInt32 {
        let value = try readNumber()
        guard let number = UInt32(exactly: value) else { throw .malformedResponse("a 32-bit number is too large") }
        return number
    }

    /// `nz-number` (RFC 9051 §9): a non-zero unsigned 32-bit decimal number, as used for UIDs and UIDVALIDITY.
    mutating func readNonZeroNumber32() throws(IMAPProtocolError) -> UInt32 {
        let value = try readNumber32()
        guard value != 0 else { throw .malformedResponse("a non-zero number was zero") }
        return value
    }

    /// A quoted string with its `\"` and `\\` escapes resolved (RFC 9051 §4.3).
    mutating func readQuoted() throws(IMAPProtocolError) -> [UInt8] {
        try expect(0x22, "a quoted string")
        var value: [UInt8] = []
        while let byte = peek() {
            position += 1
            switch byte {
            case 0x22:
                return value
            case 0x5C:
                guard let escaped = peek(), escaped == 0x22 || escaped == 0x5C else {
                    throw .malformedResponse("a quoted string contained an invalid escape")
                }
                value.append(escaped)
                position += 1
            default:
                value.append(byte)
            }
        }
        throw .malformedResponse("a quoted string was not terminated")
    }

    /// A literal's octets: its `{n}` marker must be the one the framer recorded at this position.
    mutating func readLiteral() throws(IMAPProtocolError) -> Data {
        try expect(0x7B, "a literal")
        while let byte = peek(), (0x30...0x39).contains(byte) { position += 1 }
        try expect(0x7D, "the end of a literal's size")
        guard nextLiteral < literals.count, literalEnds[nextLiteral] == position else {
            throw .malformedResponse("a literal marker did not end its line")
        }
        defer { nextLiteral += 1 }
        return literals[nextLiteral]
    }

    /// `string`: a quoted string or a literal.
    mutating func readString() throws(IMAPProtocolError) -> Data {
        switch peek() {
        case 0x22: return Data(try readQuoted())
        case 0x7B: return try readLiteral()
        default: throw .malformedResponse("expected a string")
        }
    }

    /// `nstring`: a string, or NIL (returned as nil).
    mutating func readNString() throws(IMAPProtocolError) -> Data? {
        if peek() == 0x22 || peek() == 0x7B { return try readString() }
        guard try readKeyword() == "NIL" else { throw .malformedResponse("expected a string or NIL") }
        return nil
    }

    /// `astring`: an atom (ASTRING-CHARs) or a string.
    mutating func readAString() throws(IMAPProtocolError) -> [UInt8] {
        if peek() == 0x22 || peek() == 0x7B { return [UInt8](try readString()) }
        let start = position
        while let byte = peek(), Self.isAtomChar(byte) || byte == 0x5D { position += 1 }
        guard position > start else { throw .malformedResponse("expected an atom or a string") }
        return Array(text[start..<position])
    }

    /// The bytes up to (not including) the first `terminator`, at most `maxLength` of them.
    mutating func readUntil(_ terminator: UInt8, maxLength: Int) throws(IMAPProtocolError) -> [UInt8] {
        let start = position
        while let byte = peek(), byte != terminator {
            position += 1
            guard position - start <= maxLength else { throw .malformedResponse("a field was too long") }
        }
        guard peek() == terminator else { throw .malformedResponse("a field was not terminated") }
        return Array(text[start..<position])
    }

    /// A FETCH section such as `[]` or `[HEADER.FIELDS (DATE "X-A")]`, returned without its brackets. Quoted
    /// strings and parenthesized header lists inside it are respected; at most `maxLength` bytes are accepted.
    mutating func readSection(maxLength: Int = 1_024) throws(IMAPProtocolError) -> [UInt8] {
        try expect(0x5B, "a section")
        let start = position
        var depth = 0
        var quoted = false
        while let byte = peek() {
            guard position - start <= maxLength else { throw .malformedResponse("a section was too long") }
            if quoted {
                if byte == 0x5C {
                    position += 1
                } else if byte == 0x22 {
                    quoted = false
                }
            } else if byte == 0x22 {
                quoted = true
            } else if byte == 0x28 {
                depth += 1
            } else if byte == 0x29 {
                guard depth > 0 else { throw .malformedResponse("a section's parentheses did not match") }
                depth -= 1
            } else if byte == 0x5D, depth == 0 {
                let section = Array(text[start..<position])
                position += 1
                return section
            }
            position += 1
        }
        throw .malformedResponse("a section was not terminated")
    }

    /// The characters of a sequence set (digits, `:`, `,` and `*`), unparsed.
    mutating func readSequenceSet() throws(IMAPProtocolError) -> [UInt8] {
        let start = position
        while let byte = peek(), (0x30...0x39).contains(byte) || byte == 0x3A || byte == 0x2C || byte == 0x2A {
            position += 1
        }
        guard position > start else { throw .malformedResponse("expected a sequence set") }
        return Array(text[start..<position])
    }

    /// The rest of the text (free-form response text), without interpreting it.
    mutating func readRemainder() -> [UInt8] {
        defer { position = text.count }
        return Array(text[min(position, text.count)...])
    }

    /// Skips one value of any kind: NIL, a number, an atom or flag, a quoted string, a literal, or a parenthesized
    /// list of values. Used for FETCH items and response data Lisa does not need.
    mutating func skipValue(depth: Int = 0) throws(IMAPProtocolError) {
        guard depth <= Self.maxNesting else { throw .malformedResponse("lists were nested too deeply") }
        switch peek() {
        case nil:
            throw .malformedResponse("expected a value")
        case 0x22:
            _ = try readQuoted()
        case 0x7B:
            _ = try readLiteral()
        case 0x28:
            position += 1
            var elements = 0
            while true {
                // A space next to a parenthesis is tolerated ("( )"), as some servers send it.
                if elements == 0 { _ = consume(0x20) }
                if consume(0x29) { return }
                if elements > 0 {
                    // Elements are separated by a space, except that lists may touch: BODYSTRUCTURE writes
                    // multipart bodies as "(...)(...)" (RFC 9051 §9, body-type-mpart).
                    if !consume(0x20), peek() != 0x28 { throw .malformedResponse("expected a space in a list") }
                    if consume(0x29) { return }
                }
                try skipValue(depth: depth + 1)
                elements += 1
            }
        default:
            // Atoms, numbers, flags such as \Seen or \*, and sequence sets such as 1:5,7.
            let start = position
            while let byte = peek(), Self.isLenientAtomChar(byte) { position += 1 }
            guard position > start else { throw .malformedResponse("expected a value") }
        }
    }

    /// ATOM-CHAR: any 7-bit character except atom-specials (RFC 9051 §9). `]` (resp-specials) is excluded too.
    static func isAtomChar(_ byte: UInt8) -> Bool {
        guard byte > 0x20, byte < 0x7F else { return false }
        switch byte {
        case 0x28, 0x29, 0x7B, 0x25, 0x2A, 0x22, 0x5C, 0x5D: return false
        default: return true
        }
    }

    /// The characters of a value that is only skipped: atoms, flags (`\Seen`, `\*`), numbers and sequence sets,
    /// plus 8-bit bytes, which some servers send in atoms.
    static func isLenientAtomChar(_ byte: UInt8) -> Bool {
        guard byte > 0x20, byte != 0x7F else { return false }
        switch byte {
        case 0x28, 0x29, 0x7B, 0x22, 0x5B, 0x5D: return false
        default: return true
        }
    }
}
