// Bounds on JSON5 input: document size, nesting depth and string length.

/// Bounds applied while reading a JSON5 document, so mistaken or hostile input cannot exhaust memory or the stack.
struct JSON5Limits: Hashable, Sendable {
    /// The largest document, in UTF-8 bytes.
    var maxBytes: Int
    /// The deepest nesting of objects and arrays; the top-level value is at depth 1.
    var maxDepth: Int
    /// The longest string or key, in UTF-8 bytes after escapes are decoded.
    var maxStringBytes: Int

    /// The bounds for Lisa configuration files: 1 MiB documents, 32 levels and 64 KiB strings.
    static let configuration = JSON5Limits(maxBytes: 1_048_576, maxDepth: 32, maxStringBytes: 65_536)
}
