// Keeps dry-run captures in the data directory (owner-only, bounded) so intended deliveries can be inspected later.

import Foundation
import LisaDelivery
import LisaDomain

/// Appends captures as JSON lines to `<data directory>/dry-run/captures.jsonl`, keeping at most `capacity` entries.
public final class FileDryRunRecorder: DryRunRecorder, @unchecked Sendable {
    public let url: URL
    public let capacity: Int
    private let lock = NSLock()

    public init(directory: URL, capacity: Int) throws {
        let folder = directory.appendingPathComponent("dry-run")
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        url = folder.appendingPathComponent("captures.jsonl")
        self.capacity = max(10, capacity)
    }

    public func record(_ capture: DryRunCapture) throws {
        lock.lock()
        defer { lock.unlock() }
        var lines = try readLines()
        lines.append(String(decoding: try encoder().encode(capture), as: UTF8.self))
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func recent(limit: Int) throws -> [DryRunCapture] {
        lock.lock()
        defer { lock.unlock() }
        let decoder = DomainJSON.decoder()
        return try readLines().suffix(max(0, limit)).reversed().compactMap {
            try? decoder.decode(DryRunCapture.self, from: Data($0.utf8))
        }
    }

    private func readLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private func encoder() -> JSONEncoder {
        let encoder = DomainJSON.encoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
