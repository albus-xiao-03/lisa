// RFC 5545 content lines: unfolding, then NAME;PARAM=VALUE:value splitting with quoted parameter values.

/// One unfolded content line.
public struct ContentLine: Hashable, Sendable {
    /// The property name, upper-cased.
    public let name: String
    /// Parameter values by upper-cased parameter name.
    public let parameters: [String: [String]]
    /// The raw (still escaped) value.
    public let value: String

    public init(name: String, parameters: [String: [String]], value: String) {
        self.name = name
        self.parameters = parameters
        self.value = value
    }

    /// The first value of a parameter.
    public func parameter(_ name: String) -> String? {
        parameters[name.uppercased()]?.first
    }

    /// Parses one unfolded line, or returns `nil` when it has no name/value separator.
    public static func parse(_ line: Substring) -> ContentLine? {
        var inQuotes = false
        var separator: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ":" && !inQuotes {
                separator = index
                break
            }
        }
        guard let separator else { return nil }
        let head = line[..<separator]
        let value = String(line[line.index(after: separator)...])
        let segments = splitOutsideQuotes(head, on: ";")
        guard let rawName = segments.first, !rawName.isEmpty else { return nil }
        var parameters: [String: [String]] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<equals].uppercased()
            let values = splitOutsideQuotes(segment[segment.index(after: equals)...], on: ",").map { value in
                value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2
                    ? String(value.dropFirst().dropLast()) : String(value)
            }
            parameters[key, default: []].append(contentsOf: values)
        }
        return ContentLine(name: rawName.uppercased(), parameters: parameters, value: value)
    }

    private static func splitOutsideQuotes(_ text: Substring, on separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var start = text.startIndex
        var inQuotes = false
        for index in text.indices {
            if text[index] == "\"" {
                inQuotes.toggle()
            } else if text[index] == separator && !inQuotes {
                parts.append(text[start..<index])
                start = text.index(after: index)
            }
        }
        parts.append(text[start...])
        return parts
    }
}

/// Splits calendar text into unfolded logical lines (CRLF or LF; continuation lines start with space or tab).
enum LineUnfolder {
    static func unfold(_ text: String, limits: ICalendarLimits) throws -> [Substring] {
        var lines: [Substring] = []
        var current = ""
        var hasCurrent = false
        for physical in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            var line = physical
            if line.last == "\r" { line = line.dropLast() }
            if let first = line.first, first == " " || first == "\t" {
                guard hasCurrent else { continue }
                current.append(contentsOf: line.dropFirst())
            } else {
                if hasCurrent { lines.append(Substring(current)) }
                current = String(line)
                hasCurrent = true
            }
            guard current.utf8.count <= limits.maxLineLength else { throw ICalendarError.lineTooLong }
            guard lines.count <= limits.maxLines else { throw ICalendarError.tooManyLines }
        }
        if hasCurrent { lines.append(Substring(current)) }
        return lines.filter { !$0.isEmpty }
    }
}
