// Test-only. A per-test scratch directory under the system temporary directory, removed when the test finishes
// (Phase T brief, "Runtime scratch"). Shared by every suite that touches the file system, starting with L22.

import Foundation

/// A new, empty directory that belongs to one test.
///
/// It lives under the system temporary directory, is readable only by the current user, and is removed with
/// everything in it when ``with(label:_:)`` returns or throws. It is the test program's runtime output, never a
/// repository file.
struct ScratchDirectory: Sendable {
    /// The directory itself.
    let url: URL

    /// Runs `body` with a new scratch directory, then removes the directory, whether `body` returns or throws.
    /// - Parameter label: a readable part of the directory name; the test's function name by default.
    static func with<Result>(
        label: String = #function, _ body: (ScratchDirectory) async throws -> Result
    ) async throws -> Result {
        let directory = try ScratchDirectory(label: label)
        defer { directory.remove() }
        return try await body(directory)
    }

    private init(label: String) throws {
        let readable = String(label.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(40))
        let name = "lisa-tests-\(readable)-\(UUID().uuidString.lowercased())"
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// A location inside the directory, such as `path("logs", "lisa.log")`.
    func path(_ components: String...) -> URL {
        components.reduce(url) { $0.appendingPathComponent($1) }
    }

    /// The names of the entries directly inside `directory` (by default the scratch directory itself), sorted.
    func fileNames(in directory: URL? = nil) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: (directory ?? url).path).sorted()
    }

    private func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
