// Test-only controlled substitute (plan §10): one TLS connection on 127.0.0.1, terminated by the openssl CLI's
// `s_server` with a synthetic certificate, whose plaintext a scripted server speaks through the tool's standard input
// and output. The tool binds a free port and reports it (`ACCEPT 127.0.0.1:<port>`), accepts one connection and
// exits when it closes. The client's bytes reach standard output as they arrive; the tool's own messages there are
// lines ending in a bare LF, which the mail protocols never send, so they are skipped. Each reply is written in one
// piece and starts with "*", "+" or a digit, so the tool never reads it as one of its single-letter commands. Not
// thread-safe: one dialog thread starts, uses and ends it (ScriptedDialog). Used by the scripted IMAP and SMTP
// servers (L18).

import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// The `openssl s_server` process of one scripted connection.
final class OpenSSLServerProcess {
    /// Why the tool did not start.
    struct Failed: Error, CustomStringConvertible {
        let description: String
    }

    /// The port the tool listens on, on 127.0.0.1.
    private(set) var port = 0
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer: [UInt8] = []
    private var ended = false

    /// Starts the tool with `identity`'s certificate and waits, at most `timeoutSeconds`, for its port. Its error
    /// messages go to `s_server.log` in `directory`.
    init(identity: SyntheticTLSIdentity, directory: URL, timeoutSeconds: Double = 15) throws {
        let log = directory.appendingPathComponent("s_server-\(UUID().uuidString.prefix(8)).log")
        _ = FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "openssl", "s_server", "-accept", "127.0.0.1:0", "-naccept", "1", "-cert", identity.certificateFile.path,
            "-key", identity.keyFile.path,
        ]
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle(forWritingAtPath: log.path)
        do {
            try process.run()
        } catch {
            throw Failed(description: "openssl s_server could not be started: \(error)")
        }
        let deadline = Date(timeIntervalSinceNow: timeoutSeconds)
        while port == 0 {
            guard let line = readRawLine(until: deadline, shouldStop: { false }) else {
                end()
                let reason = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                throw Failed(description: "openssl s_server reported no port: \(reason.prefix(500))")
            }
            let text = String(decoding: line, as: UTF8.self)
            if text.hasPrefix("ACCEPT 127.0.0.1:"), let value = Int(text.dropFirst(17).prefix { $0.isNumber }) {
                port = value
            }
        }
    }

    /// Blocks SIGPIPE on the calling thread, so writing to a tool that has exited fails with EPIPE instead of ending
    /// the test process. Call it first on the dialog thread.
    static func blockBrokenPipeSignals() {
        var signals = sigset_t()
        sigemptyset(&signals)
        sigaddset(&signals, SIGPIPE)
        pthread_sigmask(SIG_BLOCK, &signals, nil)
    }

    /// The next line the client sent, without its CRLF; nil once the connection has ended or `shouldStop` returns
    /// true. The tool's own messages are skipped.
    func nextLine(shouldStop: () -> Bool) -> [UInt8]? {
        while true {
            guard let line = readRawLine(until: .distantFuture, shouldStop: shouldStop) else { return nil }
            if line.count >= 2, line[line.count - 2] == 0x0D { return Array(line.dropLast(2)) }
        }
    }

    /// Sends `bytes` to the client in one write. Returns false when the tool has exited.
    @discardableResult
    func send(_ bytes: [UInt8]) -> Bool {
        let descriptor = input.fileHandleForWriting.fileDescriptor
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                return false
            }
        }
        return true
    }

    /// Sends `text` as UTF-8 in one write.
    @discardableResult
    func send(_ text: String) -> Bool {
        send(Array(text.utf8))
    }

    /// Ends the connection and the tool at once, if it is still running, and waits for it to exit. The tool inherits
    /// the test runner's threads' signal mask, in which SIGTERM is blocked, so it is ended with SIGKILL, which drops
    /// the connection as a crashed server would.
    func end() {
        guard !ended else { return }
        ended = true
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    /// The next line on the tool's standard output, with its line ending; nil at the end of the output, at
    /// `deadline` or once `shouldStop` returns true.
    private func readRawLine(until deadline: Date, shouldStop: () -> Bool) -> [UInt8]? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Array(buffer[...newline])
                buffer.removeSubrange(...newline)
                return line
            }
            if ended || shouldStop() || Date() >= deadline { return nil }
            let descriptor = output.fileHandleForReading.fileDescriptor
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 50)
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = read(descriptor, &chunk, chunk.count)
            if count > 0 {
                buffer += chunk[0..<count]
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                // The tool closed its output: the connection is over.
                end()
                return nil
            }
        }
    }
}
