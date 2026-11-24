// What every result names about the harness itself: its version, the commit it was built from and the platform.

import ArgumentParser
import Foundation
import LisaVerifyKit

enum HarnessInfo {
    static let version = "lisa-verify 1 (R2 M1)"

    /// The checkout's commit: `LISA_VERIFY_COMMIT`, else `git rev-parse HEAD` in the current directory, else "unknown".
    static func commit() -> String {
        if let value = ProcessInfo.processInfo.environment["LISA_VERIFY_COMMIT"], !value.isEmpty { return value }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "unknown"
        }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !text.isEmpty ? text : "unknown"
    }

    static var platform: String {
        #if os(macOS)
            "macOS"
        #elseif os(Linux)
            "Linux"
        #else
            "other"
        #endif
    }
}

/// The `--home` option shared by commands that use the run store.
struct StoreOptions: ParsableArguments {
    @Option(help: "The harness home (default: $LISA_VERIFY_HOME or ~/LisaVerify).")
    var home: String?

    var store: VerifyRunStore {
        VerifyRunStore(home: home.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? VerifyRunStore.defaultHome())
    }
}
