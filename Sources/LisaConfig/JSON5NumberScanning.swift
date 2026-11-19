// JSON5 numbers: decimal with optional sign, leading or trailing point and exponent, or hexadecimal.

extension JSON5Scanner {
    /// Reported for `Infinity` and `NaN`: JSON5 allows them, but no Lisa setting accepts a non-finite number.
    static let nonFiniteNumberProblem = "Infinity and NaN are not allowed here; write a finite number"

    /// Reads a number that starts at the current scalar (a sign, a digit or a decimal point).
    mutating func scanNumber() throws(JSON5Error) -> JSON5Number {
        let start = position
        var negative = false
        if current == "+" || current == "-" {
            negative = current == "-"
            advance()
        }
        if let scalar = current, Self.isIdentifierStart(scalar) {
            let word = scanWord()
            let isNonFinite = word == "Infinity" || word == "NaN"
            throw error(isNonFinite ? Self.nonFiniteNumberProblem : "expected digits after the sign", at: start)
        }
        if current == "0", peek() == "x" || peek() == "X" {
            advance()
            advance()
            return try scanHexadecimal(negative: negative, start: start)
        }
        return try scanDecimal(negative: negative, start: start)
    }

    private mutating func scanHexadecimal(negative: Bool, start: SourcePosition) throws(JSON5Error) -> JSON5Number {
        var magnitude: UInt64 = 0
        var digitCount = 0
        while let scalar = current, let digit = Self.hexValue(scalar) {
            let (shifted, overflow) = magnitude.multipliedReportingOverflow(by: 16)
            guard !overflow, shifted <= UInt64.max - UInt64(digit) else {
                throw error("this hexadecimal number is too large", at: start)
            }
            magnitude = shifted + UInt64(digit)
            digitCount += 1
            advance()
        }
        guard digitCount > 0 else {
            throw error("expected hexadecimal digits after 0x", at: start)
        }
        try requireNumberEnd()
        let limit = negative ? UInt64(Int.max) + 1 : UInt64(Int.max)
        guard magnitude <= limit else {
            throw error("this hexadecimal number is too large", at: start)
        }
        let integer = negative ? Int(truncatingIfNeeded: 0 &- magnitude) : Int(magnitude)
        return JSON5Number(doubleValue: Double(integer), integerValue: integer)
    }

    private mutating func scanDecimal(negative: Bool, start: SourcePosition) throws(JSON5Error) -> JSON5Number {
        let integerDigits = scanDigits()
        if integerDigits.count > 1, integerDigits.hasPrefix("0") {
            throw error("numbers cannot have leading zeros", at: start)
        }
        var fractionDigits: String?
        if current == "." {
            advance()
            fractionDigits = scanDigits()
        }
        guard !integerDigits.isEmpty || !(fractionDigits ?? "").isEmpty else {
            throw error("expected digits in this number", at: start)
        }
        var exponent: String?
        if current == "e" || current == "E" {
            advance()
            var sign = ""
            if current == "+" || current == "-" {
                sign = current == "-" ? "-" : "+"
                advance()
            }
            let digits = scanDigits()
            guard !digits.isEmpty else {
                throw error("expected digits after the exponent marker e", at: start)
            }
            exponent = sign + digits
        }
        try requireNumberEnd()
        var literal = negative ? "-" : ""
        literal += integerDigits.isEmpty ? "0" : integerDigits
        if let fractionDigits {
            literal += "." + (fractionDigits.isEmpty ? "0" : fractionDigits)
        }
        if let exponent {
            literal += "e" + exponent
        }
        guard let value = Double(literal), value.isFinite else {
            throw error("this number is too large", at: start)
        }
        let integer = fractionDigits == nil && exponent == nil ? Int(literal) : nil
        return JSON5Number(doubleValue: value, integerValue: integer)
    }

    private mutating func scanDigits() -> String {
        var digits = String.UnicodeScalarView()
        while let scalar = current, Self.isDecimalDigit(scalar) {
            digits.append(scalar)
            advance()
        }
        return String(digits)
    }

    /// A number must not run straight into a letter, a digit of another number or a second decimal point.
    private func requireNumberEnd() throws(JSON5Error) {
        if let scalar = current, Self.isIdentifierPart(scalar) || scalar == "." || scalar == "\\" {
            throw error("unexpected character right after a number; separate values with commas")
        }
    }
}
