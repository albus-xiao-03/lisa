// Test-only. Writes synthetic source files (.eml messages, .ics calendars, RSS feeds) into a test's scratch directory,
// with fixed modification times, because the local-file connector takes a message's arrival time from its file (D-37).
// Used by the integration and recovery suites that ingest through configured sources (L03, L05, L07, L08, L12, L13,
// L19, §16.3).

import Foundation
import LisaHost
import LisaLocalSources

/// Synthetic files for local sources. Every file is created by the test, under its scratch directory.
enum SourceFiles {
    /// Creates `directory` (and its parents) if needed and returns it.
    @discardableResult
    static func directory(_ directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `mail` to `<directory>/<name>.eml` and dates the file `receivedAt`.
    @discardableResult
    static func write(_ mail: SyntheticMail, named name: String, in directory: URL, receivedAt: Date) throws -> URL {
        let file = try Self.directory(directory).appendingPathComponent("\(name).eml")
        try write(mail.data, to: file, modifiedAt: receivedAt)
        return file
    }

    /// Writes `text` (such as a VCALENDAR or an RSS document) to `file` and dates it `modifiedAt`.
    static func write(_ text: String, to file: URL, modifiedAt: Date) throws {
        try write(Data(text.utf8), to: file, modifiedAt: modifiedAt)
    }

    /// Writes `data` to `file`, replacing it atomically, and dates it `modifiedAt`.
    static func write(_ data: Data, to file: URL, modifiedAt: Date) throws {
        try Self.directory(file.deletingLastPathComponent())
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
    }

    /// A configured directory of `.eml` messages, read as Lisa's mailbox.
    static func mailSource(_ directory: URL, key: String = "mailbox", name: String = "Lisa's mailbox") -> HostSource {
        HostSource(
            key: key, name: name, kind: .mailbox, syncIntervalSeconds: 300,
            access: .localDirectory(directory, .mail), mailboxAddress: TestHost.lisaAddress)
    }

    /// A configured `.ics` calendar file, read as a complete snapshot on every synchronization.
    static func calendarSource(
        _ file: URL, key: String = "calendar", name: String = "Work calendar", staleAfterSeconds: Int = 6 * 3600
    ) -> HostSource {
        HostSource(
            key: key, name: name, kind: .calendarFeed, staleAfterSeconds: staleAfterSeconds, syncIntervalSeconds: 300,
            access: .localFile(file, .calendar))
    }

    /// A configured RSS or Atom feed file.
    static func feedSource(_ file: URL, key: String = "feed", name: String = "Synthetic news") -> HostSource {
        HostSource(
            key: key, name: name, kind: .newsFeed, syncIntervalSeconds: 300, access: .localFile(file, .feed))
    }

    /// The source interval above, plus a second: after moving the clock this far, every configured source is due.
    static let syncIntervalMinutes = 5.0 + 1.0 / 60
}
