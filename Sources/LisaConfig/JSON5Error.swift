// Why a JSON5 document could not be read: it is too large, or has a syntax error at a line and column.

/// Why a JSON5 document could not be read. Messages describe the problem and never quote document text.
enum JSON5Error: Error, Hashable, Sendable {
    /// The document is larger than the limit; nothing was parsed.
    case tooLarge(bytes: Int, limit: Int)
    /// The document is not valid JSON5, or exceeds a structural bound, at the 1-based line and column.
    case syntax(line: Int, column: Int, problem: String)
}
