// Structured log records whose metadata values are classified so private values never reach ordinary logs.

import Foundation
import LisaRedaction

/// Severity levels.
public enum LogLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info
    case notice
    case warning
    case error

    public var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .warning: "warning"
        case .error: "error"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A metadata value. `private` values are reduced to a fingerprint; `secret` values are dropped entirely.
public enum LogValue: Sendable, Hashable {
    /// Safe to log as-is: identifiers, counts, states, error classes.
    case `public`(String)
    /// Private content (addresses, subjects, URLs, tokens): logged only as a fingerprint.
    case `private`(String)
    /// A secret: never logged in any form.
    case secret
    case count(Int)

    /// The rendered, log-safe form.
    public var rendered: String {
        switch self {
        case .public(let value): Redactor.bounded(value, limit: 512)
        case .private(let value): "fp:\(Redactor.fingerprint(value))"
        case .secret: "<redacted>"
        case .count(let value): String(value)
        }
    }
}

/// One structured log record.
public struct LogRecord: Sendable {
    public var timestamp: Date
    public var level: LogLevel
    public var category: String
    public var message: String
    public var metadata: [String: LogValue]

    public init(timestamp: Date, level: LogLevel, category: String, message: String, metadata: [String: LogValue]) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }

    /// One JSON object per line, with rendered (redacted) metadata.
    public func jsonLine() -> String {
        var object: [String: String] = [
            "ts": String(Int64((timestamp.timeIntervalSince1970 * 1000).rounded())),
            "level": level.name,
            "category": category,
            "message": Redactor.bounded(message, limit: 1024),
        ]
        for (key, value) in metadata where object[key] == nil {
            object[key] = value.rendered
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
