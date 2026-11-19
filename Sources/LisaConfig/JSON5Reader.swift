// The bounded JSON5 reader: objects, arrays and literals into a positioned value tree, rejecting duplicate keys.

/// Reads JSON5 documents (https://spec.json5.org) into positioned values, within `JSON5Limits`.
///
/// Supported: `//` and `/* */` comments, trailing commas, unquoted identifier keys, single- and double-quoted strings
/// with every JSON5 escape (including `\uXXXX` and line continuations), decimal numbers with an optional sign and a
/// leading or trailing decimal point and exponent, hexadecimal numbers, `true`, `false` and `null`.
/// Stricter than JSON5: `Infinity`, `NaN` and duplicate keys are rejected.
enum JSON5Reader {
    /// Reads `text` as one JSON5 document.
    static func read(_ text: String, limits: JSON5Limits) throws(JSON5Error) -> JSON5Node {
        let bytes = text.utf8.count
        guard bytes <= limits.maxBytes else {
            throw .tooLarge(bytes: bytes, limit: limits.maxBytes)
        }
        var parser = JSON5Parser(scanner: JSON5Scanner(text), limits: limits)
        return try parser.document()
    }
}

/// Recursive-descent parsing over a scanner; recursion is bounded by `JSON5Limits.maxDepth`.
private struct JSON5Parser {
    var scanner: JSON5Scanner
    let limits: JSON5Limits

    mutating func document() throws(JSON5Error) -> JSON5Node {
        try scanner.skipTrivia()
        guard !scanner.isAtEnd else {
            throw scanner.error("the document is empty; expected a value such as { version: 1 }")
        }
        let node = try value(depth: 0)
        try scanner.skipTrivia()
        guard scanner.isAtEnd else {
            throw scanner.error("unexpected text after the end of the document")
        }
        return node
    }

    private mutating func value(depth: Int) throws(JSON5Error) -> JSON5Node {
        let start = scanner.position
        guard let scalar = scanner.current else {
            throw scanner.error("expected a value")
        }
        switch scalar {
        case "{":
            return JSON5Node(value: .object(try object(depth: depth + 1)), position: start)
        case "[":
            return JSON5Node(value: .array(try array(depth: depth + 1)), position: start)
        case "\"", "'":
            return JSON5Node(value: .string(try scanner.scanString(maxBytes: limits.maxStringBytes)), position: start)
        case "+", "-", ".":
            return JSON5Node(value: .number(try scanner.scanNumber()), position: start)
        default:
            if JSON5Scanner.isDecimalDigit(scalar) {
                return JSON5Node(value: .number(try scanner.scanNumber()), position: start)
            }
            if JSON5Scanner.isIdentifierStart(scalar) {
                return JSON5Node(value: try literal(start: start), position: start)
            }
            throw scanner.error(
                "expected a value: an object, a list, text in quotes, a number, true, false or null", at: start)
        }
    }

    private mutating func literal(start: SourcePosition) throws(JSON5Error) -> JSON5Value {
        switch scanner.scanWord() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        case "Infinity", "NaN": throw scanner.error(JSON5Scanner.nonFiniteNumberProblem, at: start)
        default: throw scanner.error("unquoted words are not values; put text in quotes", at: start)
        }
    }

    private mutating func object(depth: Int) throws(JSON5Error) -> JSON5Object {
        let start = scanner.position
        try checkDepth(depth, at: start)
        scanner.advance()
        var members: [JSON5Member] = []
        var firstPositions: [String: SourcePosition] = [:]
        try scanner.skipTrivia()
        if scanner.current == "}" {
            scanner.advance()
            return JSON5Object(members: members)
        }
        while true {
            guard !scanner.isAtEnd else {
                throw scanner.error("this object is not closed; end it with }", at: start)
            }
            let keyPosition = scanner.position
            let key = try self.key()
            if let first = firstPositions[key] {
                throw scanner.error(
                    "this key already appears at line \(first.line), column \(first.column) of the same object; "
                        + "each key may appear only once",
                    at: keyPosition)
            }
            firstPositions[key] = keyPosition
            try scanner.skipTrivia()
            guard scanner.current == ":" else {
                throw scanner.error("expected ':' after the key")
            }
            scanner.advance()
            try scanner.skipTrivia()
            members.append(JSON5Member(key: key, keyPosition: keyPosition, value: try value(depth: depth)))
            try scanner.skipTrivia()
            switch scanner.current {
            case ",":
                scanner.advance()
                try scanner.skipTrivia()
                if scanner.current == "}" {
                    scanner.advance()
                    return JSON5Object(members: members)
                }
            case "}":
                scanner.advance()
                return JSON5Object(members: members)
            case nil:
                throw scanner.error("this object is not closed; end it with }", at: start)
            default:
                throw scanner.error("expected ',' or '}' after a value in this object")
            }
        }
    }

    private mutating func key() throws(JSON5Error) -> String {
        guard let scalar = scanner.current else {
            throw scanner.error("expected a key")
        }
        if scalar == "\"" || scalar == "'" {
            return try scanner.scanString(maxBytes: limits.maxStringBytes)
        }
        if JSON5Scanner.isIdentifierStart(scalar) || scalar == "\\" {
            return try scanner.scanIdentifierName(maxBytes: limits.maxStringBytes)
        }
        throw scanner.error("expected a key: a name such as timeZone, or text in quotes")
    }

    private mutating func array(depth: Int) throws(JSON5Error) -> [JSON5Node] {
        let start = scanner.position
        try checkDepth(depth, at: start)
        scanner.advance()
        var elements: [JSON5Node] = []
        try scanner.skipTrivia()
        if scanner.current == "]" {
            scanner.advance()
            return elements
        }
        while true {
            guard !scanner.isAtEnd else {
                throw scanner.error("this list is not closed; end it with ]", at: start)
            }
            elements.append(try value(depth: depth))
            try scanner.skipTrivia()
            switch scanner.current {
            case ",":
                scanner.advance()
                try scanner.skipTrivia()
                if scanner.current == "]" {
                    scanner.advance()
                    return elements
                }
            case "]":
                scanner.advance()
                return elements
            case nil:
                throw scanner.error("this list is not closed; end it with ]", at: start)
            default:
                throw scanner.error("expected ',' or ']' after a value in this list")
            }
        }
    }

    private func checkDepth(_ depth: Int, at position: SourcePosition) throws(JSON5Error) {
        guard depth <= limits.maxDepth else {
            throw scanner.error("objects and lists are nested more than \(limits.maxDepth) levels deep", at: position)
        }
    }
}
