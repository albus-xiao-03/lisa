// Test-only. Runs the `openssl` command-line tool on synthetic test material inside one test's scratch directory:
// certificates and keys generated at run time, and signature checks (plan §10). The tool runs on its own thread,
// never on the test's cooperative threads. Used by the adapter suites (L18, L27) and their loopback substitutes.

import Foundation

/// One run of the openssl CLI.
enum OpenSSLCommand {
    /// Why a run failed.
    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    /// How a run ended.
    struct Outcome: Sendable {
        var status: Int32
        var output: Data
        /// Standard error; openssl never prints key material there.
        var errors: String
    }

    /// Runs `openssl` with `arguments` in `directory` and returns what it wrote to standard output. A non-zero exit
    /// status throws, with the tool's standard error in the description.
    @discardableResult
    static func run(_ arguments: [String], in directory: URL) async throws -> Data {
        let outcome = try await outcome(arguments, in: directory)
        guard outcome.status == 0 else {
            throw Failed(
                description: "openssl \(arguments.first ?? "") exited with status \(outcome.status): "
                    + outcome.errors.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        }
        return outcome.output
    }

    /// Runs `openssl` with `arguments` in `directory` and returns how it ended, whatever its exit status. Only a tool
    /// that cannot be started throws.
    static func outcome(_ arguments: [String], in directory: URL) async throws -> Outcome {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result { try blockingRun(arguments, in: directory) }) }
            thread.start()
        }
    }

    private static func blockingRun(_ arguments: [String], in directory: URL) throws -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["openssl"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw Failed(description: "the openssl CLI could not be started: \(error)")
        }
        // openssl writes little to standard error, so reading standard output to its end first cannot block it.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Outcome(status: process.terminationStatus, output: data, errors: message)
    }
}
