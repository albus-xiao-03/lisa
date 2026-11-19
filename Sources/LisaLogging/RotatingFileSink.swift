// A JSON-lines log file with bounded growth: rotates at a size limit and keeps a fixed number of old files.

import Foundation
import Synchronization

/// Writes JSON lines to `<directory>/lisa.log`, rotating to `lisa.log.1 … lisa.log.N` when the size limit is reached.
public final class RotatingFileSink: LogSink {
    private struct State {
        var handle: FileHandle?
        var size: UInt64
    }

    private let directory: URL
    private let maxBytes: UInt64
    private let keepFiles: Int
    private let state: Mutex<State>

    /// - Parameters:
    ///   - maxBytes: the size at which the current file is rotated (OPS-02 log-growth bound).
    ///   - keepFiles: how many rotated files are kept.
    public init(directory: URL, maxBytes: UInt64 = 5_000_000, keepFiles: Int = 3) throws {
        self.directory = directory
        self.maxBytes = max(1024, maxBytes)
        self.keepFiles = max(1, keepFiles)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("lisa.log")
        if !FileManager.default.fileExists(atPath: file.path) {
            _ = FileManager.default.createFile(
                atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: file)
        let size = try handle.seekToEnd()
        state = Mutex(State(handle: handle, size: size))
    }

    public func write(_ record: LogRecord) {
        let line = Data((record.jsonLine() + "\n").utf8)
        state.withLock { state in
            if state.size + UInt64(line.count) > maxBytes {
                rotate(&state)
            }
            guard let handle = state.handle else { return }
            do {
                try handle.write(contentsOf: line)
                state.size += UInt64(line.count)
            } catch {
                state.handle = nil
            }
        }
    }

    private func rotate(_ state: inout State) {
        try? state.handle?.close()
        state.handle = nil
        let manager = FileManager.default
        let base = directory.appendingPathComponent("lisa.log")
        let oldest = directory.appendingPathComponent("lisa.log.\(keepFiles)")
        try? manager.removeItem(at: oldest)
        if keepFiles > 1 {
            for index in stride(from: keepFiles - 1, through: 1, by: -1) {
                let from = directory.appendingPathComponent("lisa.log.\(index)")
                let to = directory.appendingPathComponent("lisa.log.\(index + 1)")
                if manager.fileExists(atPath: from.path) { try? manager.moveItem(at: from, to: to) }
            }
        }
        try? manager.moveItem(at: base, to: directory.appendingPathComponent("lisa.log.1"))
        _ = manager.createFile(atPath: base.path, contents: nil, attributes: [.posixPermissions: 0o600])
        state.handle = try? FileHandle(forWritingTo: base)
        state.size = 0
    }
}
