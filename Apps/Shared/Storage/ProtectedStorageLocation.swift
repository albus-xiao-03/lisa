// Where the app keeps its client files: a directory of its own in Application Support, protected until first unlock
// on iPhone and iPad, owner-only, and left out of backups.

import Foundation

/// The directory of this app's client files (UI-03, plan §6.5, SEC-03): the offline queue (`queue/`), the response
/// cache (`cache/`) and the connection settings (`connection.json`), as `ClientServices` and
/// `HostConnectionController` lay them out.
///
/// - It is `Application Support/<bundle identifier>/Client`, with mode 0700; the client's files inside are 0600.
/// - On iPhone and iPad the directories and every file written in them use
///   `FileProtectionType.completeUntilFirstUserAuthentication`: once the device has been unlocked after a restart
///   they stay readable and writable while it is locked, so actions taken on the lock screen can be queued. On the
///   Mac the files rely on the user account's permissions and FileVault.
/// - It is excluded from backups. The device credential stays on this device only, so a restored queue, cache or
///   address would belong to a pairing the restored device no longer has.
struct ProtectedStorageLocation: Sendable {
    /// The client directory.
    let directory: URL

    /// The data-protection options of every client file write.
    static var fileProtection: Data.WritingOptions {
        #if os(iOS)
            return .completeFileProtectionUntilFirstUserAuthentication
        #else
            return []
        #endif
    }

    /// The connection settings file.
    var connectionSettingsFile: URL { directory.appendingPathComponent("connection.json") }

    /// This app's client directory, created and protected when needed.
    static func standard() throws -> ProtectedStorageLocation {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent(try ThisAppBuild.requiredBundleIdentifier(), isDirectory: true)
            .appendingPathComponent("Client", isDirectory: true)
        try prepare(directory)
        for name in ["queue", "cache"] {
            try prepare(directory.appendingPathComponent(name, isDirectory: true))
        }
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return ProtectedStorageLocation(directory: directory)
    }

    /// Creates `directory` with mode 0700 and, on iPhone and iPad, the protection class, or applies them to it.
    private static func prepare(_ directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.setAttributes(attributes, ofItemAtPath: directory.path)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        }
    }
}
