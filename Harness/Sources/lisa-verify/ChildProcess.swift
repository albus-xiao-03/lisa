// Running this same executable as a child process, so S-24's interruption variants kill a real process and resume in
// a new one (plan §10.8 acceptance).

import Foundation

enum ChildProcess {
    struct Result: Sendable {
        let status: Int32
        let killedBySignal: Bool
        let output: String
    }

    static var executable: URL {
        Bundle.main.executableURL ?? URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
    }

    /// Runs `lisa-verify <arguments>`, feeding `input` on standard input, and waits for it without blocking a thread.
    static func run(_ arguments: [String], input: String? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        let stdin = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = stdin
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: Result(
                        status: finished.terminationStatus,
                        killedBySignal: finished.terminationReason == .uncaughtSignal,
                        output: String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
                if let input { stdin.fileHandleForWriting.write(Data((input + "\n").utf8)) }
                try? stdin.fileHandleForWriting.close()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
