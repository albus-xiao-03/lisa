// Writes log records to standard error, for interactive and headless runs.

import Foundation

/// Writes each record as a JSON line to standard error.
public struct StandardErrorSink: LogSink {
    public init() {}

    public func write(_ record: LogRecord) {
        FileHandle.standardError.write(Data((record.jsonLine() + "\n").utf8))
    }
}

/// Fans a record out to several sinks.
public struct MultiplexSink: LogSink {
    private let sinks: [any LogSink]

    public init(_ sinks: [any LogSink]) {
        self.sinks = sinks
    }

    public func write(_ record: LogRecord) {
        for sink in sinks { sink.write(record) }
    }
}
