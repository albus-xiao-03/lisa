// Test-only controlled substitute (plan §10): runs one scripted server conversation on its own thread, over one TLS
// connection that `openssl s_server` terminates on 127.0.0.1 (OpenSSLServerProcess). The server's greeting is queued
// before the client connects, the dialog reads the client's lines and writes replies, and stopping ends the
// conversation and the tool. Blocking reads and writes never run on the test's cooperative threads. Used by the
// scripted IMAP and SMTP servers (L18).

import Foundation
import Synchronization

/// A scripted conversation in progress.
final class ScriptedDialog: Sendable {
    private struct State {
        var stopRequested = false
        var finished = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private final class Control: Sendable {
        let state = Mutex(State())

        var stopRequested: Bool { state.withLock { $0.stopRequested } }

        func requestStop() {
            state.withLock { $0.stopRequested = true }
        }

        func finish() {
            let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.finished = true
                defer { state.waiters.removeAll() }
                return state.waiters
            }
            for waiter in waiters { waiter.resume() }
        }

        func waitUntilFinished() async {
            await withCheckedContinuation { continuation in
                let done = state.withLock { state -> Bool in
                    if state.finished { return true }
                    state.waiters.append(continuation)
                    return false
                }
                if done { continuation.resume() }
            }
        }
    }

    /// The port the client connects to, on 127.0.0.1.
    let port: Int
    private let control: Control

    private init(port: Int, control: Control) {
        self.port = port
        self.control = control
    }

    /// Starts `openssl s_server` with `identity` in `directory`, queues `greeting`, and runs `dialog` on a new
    /// thread once the port is known. `dialog` gets the connection and a check that tells it to stop.
    static func start(
        identity: SyntheticTLSIdentity, directory: URL, greeting: String,
        dialog: @escaping @Sendable (OpenSSLServerProcess, _ shouldStop: () -> Bool) -> Void
    ) async throws -> ScriptedDialog {
        let control = Control()
        let port: Int = try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                OpenSSLServerProcess.blockBrokenPipeSignals()
                let connection: OpenSSLServerProcess
                do {
                    connection = try OpenSSLServerProcess(identity: identity, directory: directory)
                } catch {
                    control.finish()
                    continuation.resume(throwing: error)
                    return
                }
                // The tool reads its input only once a client has connected, so the greeting waits for the client.
                connection.send(greeting)
                continuation.resume(returning: connection.port)
                dialog(connection, { control.stopRequested })
                connection.end()
                control.finish()
            }
            thread.start()
        }
        return ScriptedDialog(port: port, control: control)
    }

    /// Ends the conversation, if it has not ended, and waits until the tool has exited.
    func stop() async {
        control.requestStop()
        await control.waitUntilFinished()
    }

    /// Waits until the client has ended the conversation (or the server did), at most `limit`. Returns whether it did.
    func waitUntilFinished(within limit: Duration) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !control.state.withLock({ $0.finished }) {
            guard ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}
