// The logger used throughout Lisa: a category plus a sink, with level filtering.

import Foundation

/// Receives log records.
public protocol LogSink: Sendable {
    func write(_ record: LogRecord)
}

/// A category-scoped logger.
public struct Logger: Sendable {
    public let category: String
    private let sink: any LogSink
    private let minimumLevel: LogLevel

    public init(category: String, sink: any LogSink, minimumLevel: LogLevel = .info) {
        self.category = category
        self.sink = sink
        self.minimumLevel = minimumLevel
    }

    /// A logger that discards everything.
    public static let disabled = Logger(category: "disabled", sink: DiscardingSink(), minimumLevel: .error)

    /// A logger for another category sharing this logger's sink and level.
    public func scoped(_ category: String) -> Logger {
        Logger(category: category, sink: sink, minimumLevel: minimumLevel)
    }

    public func log(_ level: LogLevel, _ message: String, _ metadata: [String: LogValue] = [:]) {
        guard level >= minimumLevel else { return }
        sink.write(LogRecord(timestamp: Date(), level: level, category: category, message: message, metadata: metadata))
    }

    public func debug(_ message: String, _ metadata: [String: LogValue] = [:]) { log(.debug, message, metadata) }

    public func info(_ message: String, _ metadata: [String: LogValue] = [:]) { log(.info, message, metadata) }

    public func notice(_ message: String, _ metadata: [String: LogValue] = [:]) { log(.notice, message, metadata) }

    public func warning(_ message: String, _ metadata: [String: LogValue] = [:]) { log(.warning, message, metadata) }

    public func error(_ message: String, _ metadata: [String: LogValue] = [:]) { log(.error, message, metadata) }
}

/// Discards every record.
public struct DiscardingSink: LogSink {
    public init() {}

    public func write(_ record: LogRecord) {}
}
