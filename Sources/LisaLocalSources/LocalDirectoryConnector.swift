// Imports local source files (INGEST-01, CLI-01 `lisa import`): mail (.eml), calendars (.ics) and feeds (.xml).

import Foundation
import LisaDomain
import LisaPorts

/// What a local directory holds.
public enum LocalSourceFormat: String, Codable, Hashable, Sendable, CaseIterable {
    case mail
    case calendar
    case feed

    var extensions: Set<String> {
        switch self {
        case .mail: ["eml"]
        case .calendar: ["ics"]
        case .feed: ["xml", "rss", "atom"]
        }
    }

    var itemKind: FetchedItemKind {
        switch self {
        case .mail: .email
        case .calendar: .calendar
        case .feed: .feed
        }
    }
}

/// Reads files from one directory, never following symbolic links or descending into subdirectories.
///
/// - Mail is incremental: files are taken in name order after the cursor (the last file name processed), so
///   re-running never re-reads processed files; a message's key is its file name.
/// - Calendars and feeds are complete snapshots: every file is read on every run, so a calendar file that loses an
///   event lets reconciliation cancel it.
public struct LocalDirectoryConnector: SourceConnector {
    public let kind: SourceKind = .localImport
    public let directory: URL
    public let format: LocalSourceFormat
    /// When set, only this file in the directory is read (a single configured calendar or feed file).
    public let fileName: String?

    public init(directory: URL, format: LocalSourceFormat) {
        self.directory = directory
        self.format = format
        self.fileName = nil
    }

    /// Reads exactly one file, such as a configured `.ics` calendar.
    public init(file: URL, format: LocalSourceFormat) {
        self.directory = file.deletingLastPathComponent()
        self.format = format
        self.fileName = file.lastPathComponent
    }

    public func validateConfiguration() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw ConnectorError(.configuration, "the import directory does not exist or is not a directory")
        }
        guard FileManager.default.isReadableFile(atPath: directory.path) else {
            throw ConnectorError(.permissionDenied, "the import directory is not readable")
        }
    }

    public func fetch(cursor: String?, limits: SyncLimits) async throws -> FetchBatch {
        let files = try candidates()
        // A configured file that cannot be read is a failed refresh, never an empty snapshot: an empty complete
        // snapshot would cancel every event the file held (CAL-02, D-32).
        if let fileName, !files.contains(where: { $0.name == fileName }) {
            throw ConnectorError(
                .configuration,
                "the configured file \(fileName) is missing or is not a regular \(format.rawValue) file")
        }
        switch format {
        case .mail:
            let pending = files.filter { cursor == nil || $0.name > cursor! }
            return try batch(pending, limits: limits, snapshot: false, previousCursor: cursor)
        case .calendar, .feed:
            return try batch(files, limits: limits, snapshot: true, previousCursor: nil)
        }
    }

    struct Candidate {
        var name: String
        var url: URL
        var size: Int
        var modified: Date
    }

    func candidates() throws -> [Candidate] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        } catch {
            throw ConnectorError(.permissionDenied, "the import directory could not be listed")
        }
        return entries.compactMap { url -> Candidate? in
            guard fileName == nil || url.lastPathComponent == fileName,
                format.extensions.contains(url.pathExtension.lowercased()),
                let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                values.isRegularFile == true
            else { return nil }
            return Candidate(
                name: url.lastPathComponent, url: url, size: values.fileSize ?? 0,
                modified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0))
        }.sorted { $0.name < $1.name }
    }

    func batch(_ files: [Candidate], limits: SyncLimits, snapshot: Bool, previousCursor: String?) throws -> FetchBatch {
        var items: [FetchedItem] = []
        var notes: [String] = []
        var bytes = 0
        var lastTaken: String?
        for file in files {
            if file.size > limits.maxBytes {
                // A snapshot without one of its files is not complete; read as complete, it would cancel every event
                // or item that file held (CAL-02, D-32).
                if snapshot {
                    throw ConnectorError(
                        .partial,
                        "\(file.name) is larger than \(limits.maxBytes) bytes; the snapshot was not read in full")
                }
                notes.append("\(file.name) is larger than \(limits.maxBytes) bytes and was skipped")
                lastTaken = file.name
                continue
            }
            if items.count >= limits.maxItems || bytes + file.size > limits.maxBytes {
                if snapshot {
                    throw ConnectorError(.partial, "the directory holds more data than one pass may read")
                }
                return FetchBatch(
                    items: items, nextCursor: lastTaken ?? previousCursor, isCompleteSnapshot: false, hasMore: true,
                    capabilityNotes: notes)
            }
            let data: Data
            do {
                data = try Data(contentsOf: file.url)
            } catch {
                throw ConnectorError(.permissionDenied, "\(file.name) could not be read")
            }
            bytes += data.count
            items.append(
                FetchedItem(
                    externalID: "file:\(file.name)", kind: format.itemKind, data: data, receivedAt: file.modified,
                    metadata: ["fileName": file.name]))
            lastTaken = file.name
        }
        return FetchBatch(
            items: items, nextCursor: snapshot ? nil : (lastTaken ?? previousCursor), isCompleteSnapshot: snapshot,
            hasMore: false, capabilityNotes: notes)
    }
}
