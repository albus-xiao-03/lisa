// Path rules: a leading ~ expands to the home directory, and every configured path must end up absolute.

import Foundation

/// Rules for file-system paths in the configuration. Relative paths are refused, so a path never depends on the
/// directory a command happens to run in.
enum FilePathRules {
    /// Expands `~` and `~/…` with `homeDirectory`, requires an absolute result, and removes `.` and `..` components.
    static func absolutePath(_ text: String, homeDirectory: String) -> Result<String, ValueRefusal> {
        var path = text
        if path == "~" {
            path = homeDirectory
        } else if path.hasPrefix("~/") {
            path = homeDirectory + path.dropFirst()
        } else if path.hasPrefix("~") {
            return .failure(ValueRefusal("~user paths are not supported; write an absolute path or start with ~/"))
        }
        guard path.hasPrefix("/") else {
            return .failure(ValueRefusal("must be an absolute path, or start with ~/ for the home directory"))
        }
        return .success(URL(fileURLWithPath: path).standardized.path)
    }
}
