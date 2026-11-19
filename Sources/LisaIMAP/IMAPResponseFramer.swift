// Splits the server's byte stream into complete IMAP responses (RFC 9051 §4.3, §7): CRLF-terminated lines with
// embedded literals, where every size is checked before anything is stored.

import Foundation

/// The bounds the framer enforces while one command's responses are read.
struct IMAPFramingLimits: Hashable, Sendable {
    /// The longest response text, literal data excluded.
    var maxLineBytes: Int
    /// The largest single literal.
    var maxLiteralBytes: Int
    /// The most literals in one response.
    var maxLiteralsPerResponse: Int
    /// The most literal octets in total, counted from the moment these limits are set.
    var literalBudget: Int
}

/// Turns received bytes into complete responses. Only the response being read is kept; a literal is accepted only
/// after its announced size has passed the limits, so a hostile size never causes an allocation.
struct IMAPResponseFramer {
    private(set) var limits: IMAPFramingLimits
    private var remainingBudget: Int
    private var text: [UInt8] = []
    private var literals: [Data] = []
    private var literalEnds: [Int] = []
    private var literal = Data()
    private var literalRemaining = 0
    private var readingLiteral = false
    private var crPending = false

    init(limits: IMAPFramingLimits) {
        self.limits = limits
        remainingBudget = max(0, limits.literalBudget)
    }

    /// Replaces the limits, for example before the next command; the literal budget starts again.
    mutating func setLimits(_ limits: IMAPFramingLimits) {
        self.limits = limits
        remainingBudget = max(0, limits.literalBudget)
    }

    /// Whether part of a response has been received but not yet completed.
    var isMidResponse: Bool { !text.isEmpty || !literals.isEmpty || readingLiteral || crPending }

    /// Whether the framer is inside a literal's octets.
    var isReadingLiteral: Bool { readingLiteral }

    /// Consumes `bytes` and returns the responses they complete, in order.
    mutating func feed(_ bytes: [UInt8]) throws(IMAPProtocolError) -> [IMAPRawResponse] {
        var responses: [IMAPRawResponse] = []
        var index = 0
        while index < bytes.count {
            if readingLiteral {
                let count = min(literalRemaining, bytes.count - index)
                bytes.withUnsafeBufferPointer { buffer in
                    literal.append(UnsafeBufferPointer(rebasing: buffer[index..<(index + count)]))
                }
                literalRemaining -= count
                index += count
                if literalRemaining == 0 { finishLiteral() }
                continue
            }
            let newline = bytes[index...].firstIndex(of: 0x0A)
            let end = newline ?? bytes.count
            try appendLineBytes(bytes[index..<end], endsLine: newline != nil)
            guard newline != nil else { break }
            index = end + 1
            if let response = try completeLine() { responses.append(response) }
        }
        return responses
    }

    /// Adds line bytes that precede a line feed (`endsLine`) or the end of the received bytes. A carriage return
    /// is allowed only directly before the line feed, which may arrive with the next bytes.
    private mutating func appendLineBytes(_ segment: ArraySlice<UInt8>, endsLine: Bool) throws(IMAPProtocolError) {
        if crPending {
            guard segment.isEmpty, endsLine else {
                throw .malformedLine("a carriage return was not followed by a line feed")
            }
            crPending = false
            return
        }
        var body = segment
        var endsWithCR = false
        if body.last == 0x0D {
            body = body.dropLast()
            endsWithCR = true
        }
        if body.contains(0x00) { throw .malformedLine("it contained a NUL byte") }
        if body.contains(0x0D) { throw .malformedLine("a carriage return was not followed by a line feed") }
        guard text.count + body.count <= limits.maxLineBytes else { throw .lineTooLong(limit: limits.maxLineBytes) }
        text.append(contentsOf: body)
        if endsLine {
            guard endsWithCR else { throw .malformedLine("a line was not ended by CRLF") }
        } else {
            crPending = endsWithCR
        }
    }

    /// Ends the current line: either it announces a literal, or the response is complete.
    private mutating func completeLine() throws(IMAPProtocolError) -> IMAPRawResponse? {
        if let declared = try literalAnnouncement() {
            guard literals.count < limits.maxLiteralsPerResponse else {
                throw .tooManyLiterals(limit: limits.maxLiteralsPerResponse)
            }
            guard declared <= UInt64(max(0, limits.maxLiteralBytes)) else {
                throw .literalTooLarge(declared: declared, limit: limits.maxLiteralBytes)
            }
            guard declared <= UInt64(remainingBudget) else {
                throw .literalBudgetExceeded(limit: limits.literalBudget)
            }
            let count = Int(declared)
            remainingBudget -= count
            literalEnds.append(text.count)
            literal = Data()
            literal.reserveCapacity(count)
            literalRemaining = count
            readingLiteral = true
            if count == 0 { finishLiteral() }
            return nil
        }
        let response = IMAPRawResponse(text: text, literals: literals, literalEnds: literalEnds)
        text = []
        literals = []
        literalEnds = []
        return response
    }

    /// The octet count of a `{n}` marker that ends the current text, if there is one.
    private func literalAnnouncement() throws(IMAPProtocolError) -> UInt64? {
        guard text.last == 0x7D else { return nil }
        var index = text.count - 2
        var nonSynchronizing = false
        if index >= 0, text[index] == 0x2B {
            nonSynchronizing = true
            index -= 1
        }
        let digitsEnd = index + 1
        while index >= 0, (0x30...0x39).contains(text[index]) { index -= 1 }
        let digitCount = digitsEnd - (index + 1)
        guard index >= 0, text[index] == 0x7B, digitCount > 0 else { return nil }
        if nonSynchronizing { throw .nonSynchronizingLiteral }
        // number64 has at most 19 digits (RFC 9051 §9); anything longer cannot be accepted anyway.
        guard digitCount <= 19 else { throw .literalTooLarge(declared: UInt64.max, limit: limits.maxLiteralBytes) }
        var value: UInt64 = 0
        for byte in text[(index + 1)..<digitsEnd] { value = value * 10 + UInt64(byte - 0x30) }
        return value
    }

    private mutating func finishLiteral() {
        literals.append(literal)
        literal = Data()
        literalRemaining = 0
        readingLiteral = false
    }
}
