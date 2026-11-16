// Loading the configuration (CFG-01): a bounded UTF-8 file that other users cannot modify, parsed and validated.

import Foundation

/// Reads and validates Lisa's versioned JSON5 configuration. Either every setting is valid, or the error lists every
/// issue found; there is no partially valid configuration.
public enum ConfigurationLoader {
    /// The configuration schema version this Lisa reads.
    public static let supportedVersion = 1
    /// The largest configuration accepted, in bytes (1 MiB).
    public static let maxFileBytes = JSON5Limits.configuration.maxBytes

    /// Reads, parses and validates the configuration file at `path`.
    ///
    /// The file must be a regular file of at most 1 MiB of UTF-8 text, and other users must not be able to modify it,
    /// because it decides whom Lisa may contact. A leading `~` in configured paths expands to `homeDirectory`.
    public static func load(path: String, homeDirectory: String = NSHomeDirectory()) throws(ConfigurationError)
        -> LisaConfiguration
    {
        let text = try readText(at: path)
        return try parse(text: text, sourceName: path, homeDirectory: homeDirectory)
    }

    /// Parses and validates configuration text. `sourceName` says where the text came from, such as a file path.
    public static func parse(text: String, sourceName: String, homeDirectory: String = NSHomeDirectory())
        throws(ConfigurationError) -> LisaConfiguration
    {
        let root: JSON5Node
        do {
            root = try JSON5Reader.read(text, limits: .configuration)
        } catch {
            switch error {
            case .tooLarge(let bytes, let limit):
                throw ConfigurationError.tooLarge(bytes: bytes, limit: limit)
            case .syntax(let line, let column, let problem):
                throw ConfigurationError.syntax(line: line, column: column, problem: problem)
            }
        }
        return try ConfigurationDecoder(sourceName: sourceName, homeDirectory: homeDirectory).decode(root)
    }

    private static func readText(at path: String) throws(ConfigurationError) -> String {
        let manager = FileManager.default
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ConfigurationError.unreadable(path: path, reason: "it does not exist")
        }
        guard !isDirectory.boolValue else {
            throw ConfigurationError.unreadable(path: path, reason: "it is a directory, not a file")
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try manager.attributesOfItem(atPath: url.path)
        } catch {
            throw ConfigurationError.unreadable(path: path, reason: "its file attributes could not be read")
        }
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw ConfigurationError.unreadable(path: path, reason: "it is not a regular file")
        }
        if let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue, permissions & 0o002 != 0 {
            throw ConfigurationError.unreadable(
                path: path,
                reason: "other users can modify it, and it decides whom Lisa may contact; "
                    + "remove their write permission with chmod o-w")
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxFileBytes else {
            throw ConfigurationError.tooLarge(bytes: size, limit: maxFileBytes)
        }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // One byte more than the limit reveals a file that grew after its size was checked.
            data = try handle.read(upToCount: maxFileBytes + 1) ?? Data()
        } catch {
            let reason =
                manager.isReadableFile(atPath: url.path) ? "it could not be read" : "permission to read it is denied"
            throw ConfigurationError.unreadable(path: path, reason: reason)
        }
        guard data.count <= maxFileBytes else {
            throw ConfigurationError.tooLarge(bytes: max(size, data.count), limit: maxFileBytes)
        }
        guard let text = String(validating: data, as: UTF8.self) else {
            throw ConfigurationError.unreadable(path: path, reason: "it is not valid UTF-8 text")
        }
        return text
    }
}
