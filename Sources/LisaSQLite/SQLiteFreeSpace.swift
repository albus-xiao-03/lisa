// Free space on the file system that holds a database (plan §8.15.2): what an unprivileged writer can still use, read
// fresh with `statvfs` each time it is asked.

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Free-space readings for storage decisions.
public enum SQLiteFreeSpace {
    /// The bytes available to an unprivileged writer on the file system holding `path` (`f_bavail × f_frsize`), or
    /// `nil` if it can't be read.
    public static func availableBytes(at path: String) -> Int64? {
        var info = statvfs()
        guard statvfs(path, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_frsize)
    }
}
