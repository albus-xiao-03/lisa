// Located configuration values: typed conversions that report issues at the value's path and never quote it.

import LisaSecrets
import LisaTime

/// Why a format rule refused a value: the problem and, when useful, how to fix it. It never quotes the value.
struct ValueRefusal: Error, Hashable, Sendable {
    let problem: String
    let fix: String?

    init(_ problem: String, fix: String? = nil) {
        self.problem = problem
        self.fix = fix
    }
}

/// A value being decoded, with its path. Each conversion either returns the typed value or reports one issue.
struct ConfigValue {
    let node: JSON5Node
    let path: ConfigurationPath
    let context: DecodingContext

    var position: SourcePosition { node.position }

    func report(_ problem: String, fix: String? = nil) {
        context.report(path, at: node.position, problem, fix: fix)
    }

    /// The value's type for messages; types are safe to show, values are not.
    var typeDescription: String {
        switch node.value {
        case .null: "null"
        case .bool: "true or false"
        case .number: "a number"
        case .string: "text"
        case .array: "a list"
        case .object: "an object"
        }
    }

    /// Non-empty text without control characters, bidirectional overrides or surrounding spaces.
    func text(maxLength: Int = 256) -> String? {
        guard case .string(let text) = node.value else {
            report("must be text in quotes, not \(typeDescription)")
            return nil
        }
        guard !text.isEmpty else {
            report("must not be empty", fix: "write null or remove the setting to leave it unset")
            return nil
        }
        guard text.unicodeScalars.count <= maxLength else {
            report("must be at most \(maxLength) characters long")
            return nil
        }
        guard !text.unicodeScalars.contains(where: Self.isDisallowedScalar) else {
            report("must not contain control characters such as line breaks or tabs")
            return nil
        }
        guard text.first?.isWhitespace != true, text.last?.isWhitespace != true else {
            report("must not start or end with spaces")
            return nil
        }
        return text
    }

    /// Text that also satisfies `rule`.
    func validated<T>(maxLength: Int = 256, _ rule: (String) -> Result<T, ValueRefusal>) -> T? {
        guard let text = text(maxLength: maxLength) else { return nil }
        switch rule(text) {
        case .success(let value):
            return value
        case .failure(let refusal):
            report(refusal.problem, fix: refusal.fix)
            return nil
        }
    }

    /// A whole number within `range`. `5`, `5.0`, `5e0` and `0x5` are all accepted as 5.
    func integer(in range: ClosedRange<Int>) -> Int? {
        let bounds = "between \(range.lowerBound) and \(range.upperBound)"
        guard case .number(let number) = node.value else {
            report("must be a whole number \(bounds), without quotes, not \(typeDescription)")
            return nil
        }
        guard let integer = number.exactInteger else {
            report("must be a whole number \(bounds)")
            return nil
        }
        guard range.contains(integer) else {
            report("must be \(bounds)")
            return nil
        }
        return integer
    }

    /// A finite number within `range`.
    func number(in range: ClosedRange<Double>) -> Double? {
        let bounds = "between \(Self.display(range.lowerBound)) and \(Self.display(range.upperBound))"
        guard case .number(let number) = node.value else {
            report("must be a number \(bounds), without quotes, not \(typeDescription)")
            return nil
        }
        guard range.contains(number.doubleValue) else {
            report("must be \(bounds)")
            return nil
        }
        return number.doubleValue
    }

    func bool() -> Bool? {
        guard case .bool(let flag) = node.value else {
            report("must be true or false, without quotes, not \(typeDescription)")
            return nil
        }
        return flag
    }

    /// One of `options`, matched exactly; a case-only mismatch gets a hint.
    func choice<T: RawRepresentable>(of options: [T]) -> T? where T.RawValue == String {
        let names = options.map(\.rawValue).joined(separator: ", ")
        guard case .string(let text) = node.value else {
            report("must be one of \(names), in quotes, not \(typeDescription)")
            return nil
        }
        if let match = options.first(where: { $0.rawValue == text }) {
            return match
        }
        let hint = options.first { $0.rawValue.lowercased() == text.lowercased() }.map {
            "values are case-sensitive: write \($0.rawValue)"
        }
        report("must be one of \(names)", fix: hint)
        return nil
    }

    /// A time of day written `HH:MM` in 24-hour form.
    func localTime() -> LocalTime? {
        guard case .string(let text) = node.value, text.utf8.count == 5, let time = LocalTime(iso: text) else {
            report("must be a time of day written HH:MM in 24-hour form, such as \"07:30\"")
            return nil
        }
        return time
    }

    /// A known IANA time-zone identifier, such as `America/New_York`.
    func timeZone() -> TimeZoneID? {
        guard case .string(let text) = node.value, let zone = TimeZoneID(text) else {
            report(
                "must be an IANA time-zone identifier known to this system, such as \"America/New_York\" or \"UTC\"")
            return nil
        }
        return zone
    }

    /// A reference to a secret kept outside the configuration: `env:NAME`, `file:/path` or `keychain:service/account`.
    func secretReference() -> SecretReference? {
        guard case .string(let text) = node.value, let reference = SecretReference(text) else {
            report(
                "must be a secret reference: env:NAME, file:/absolute/path or keychain:service/account",
                fix: "keep the secret itself in an environment variable, a protected file (mode 0600) or the Keychain, "
                    + "never in this file")
            return nil
        }
        return reference
    }

    /// The elements of a list, each with its indexed path.
    func elements(maxCount: Int) -> [ConfigValue]? {
        guard case .array(let nodes) = node.value else {
            report("must be a list in square brackets [ ], not \(typeDescription)")
            return nil
        }
        guard nodes.count <= maxCount else {
            report("must have at most \(maxCount) entries")
            return nil
        }
        return nodes.enumerated().map { index, element in
            let elementPath = path.appending(index: index)
            context.record(elementPath, at: element.position)
            return ConfigValue(node: element, path: elementPath, context: context)
        }
    }

    /// The value as a section, when it is an object.
    func section() -> ConfigSection? {
        guard case .object(let object) = node.value else {
            report("must be an object in braces { }, not \(typeDescription)")
            return nil
        }
        return ConfigSection(object, path: path, position: node.position, context: context)
    }

    /// Control characters, line and paragraph separators (which JSON5 allows inside strings), and bidirectional
    /// formatting characters that can disguise text (such as U+202E).
    private static func isDisallowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator: return true
        default: break
        }
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
        default: return false
        }
    }

    private static func display(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
