// Actionable configuration errors (CFG-01): where the problem is, what is wrong and how to fix it.

import Foundation

/// One problem found while validating a configuration file. It names the setting and its position, never its value.
public struct ConfigurationIssue: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The setting's path, such as `sources[2].passwordSecret` or `delivery.approvedEmailAddresses[0]`.
    public var path: String
    /// What is wrong with the setting.
    public var problem: String
    /// What to change, when it is not obvious from the problem.
    public var fix: String?
    /// The 1-based line of the setting in the file, when known.
    public var line: Int?
    /// The 1-based column of the setting in the file, when known.
    public var column: Int?

    public init(path: String, problem: String, fix: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.path = path
        self.problem = problem
        self.fix = fix
        self.line = line
        self.column = column
    }

    public var description: String {
        var text = path
        if let line {
            text += column.map { " (line \(line), column \($0))" } ?? " (line \(line))"
        }
        text += ": \(problem)"
        if let fix {
            text += " (\(fix))"
        }
        return text
    }
}

/// Why a configuration file was rejected. Messages name settings and positions, never secret values.
public enum ConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The file is missing, not a regular file, unreadable, not UTF-8, or writable by other users.
    case unreadable(path: String, reason: String)
    /// The file is larger than the limit; nothing was parsed.
    case tooLarge(bytes: Int, limit: Int)
    /// The text is not valid JSON5, or exceeds a nesting or string bound, at the 1-based line and column.
    case syntax(line: Int, column: Int, problem: String)
    /// The `version` is missing or not one this Lisa reads; nothing else was interpreted.
    case unsupportedVersion(found: Int?, supported: Int)
    /// Every issue found in the settings, in document order.
    case invalid([ConfigurationIssue])

    public var description: String {
        switch self {
        case .unreadable(let path, let reason):
            "the configuration file \(path) could not be read: \(reason)"
        case .tooLarge(let bytes, let limit):
            "the configuration file has \(bytes) bytes; the limit is \(limit)"
        case .syntax(let line, let column, let problem):
            "configuration syntax error at line \(line), column \(column): \(problem)"
        case .unsupportedVersion(let found, let supported):
            "the configuration declares version \(found.map(String.init) ?? "(missing)"); "
                + "this Lisa reads version \(supported)"
        case .invalid(let issues):
            "the configuration is invalid:\n" + issues.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}
