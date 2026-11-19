// One run of the embedded host: the host opened under the data-directory lock, its network API with the owner endpoint
// file, its processing loop, and shutdown in the order `lisa serve` uses (plan §5.2).

import Foundation
import LisaClient
import LisaHost
import LisaRuntime
import Synchronization

/// The host the app runs in process (ARCH-03, D-50), from start to shutdown.
///
/// - Start, as `lisa serve` does: the network API (the configured device listener for paired devices and the loopback
///   owner listener), then the owner endpoint file with the owner listener's port and this run's owner credential, so
///   `lisa` commands run meanwhile connect to the app as clients; then the processing loop. When the API can't be
///   served, the host still runs for the app's own screens, and `apiProblem` says why companions and `lisa` commands
///   can't reach it.
/// - Shutdown, in reverse order: the network server (requests in progress finish), the owner endpoint file, the
///   processing loop (the current cycle finishes), then the data-directory lock. When a grace period is given and the
///   loop has not finished by then, the lock is not released early: the app quits and the system releases it, so no
///   second writer can open the data directory while this one may still write.
@MainActor
final class EmbeddedHostSession {
    /// The open host.
    let host: LisaHost
    /// Why the network API is not served, if it is not.
    private(set) var apiProblem: String?
    /// The owner listener's port on 127.0.0.1 while the API is served.
    private(set) var ownerPort: Int?

    private var server: HostAPIServer?
    private var wroteEndpoint = false
    private var runtime: Task<Void, Never>?
    private let endpointFile: OwnerEndpointFile

    private init(host: LisaHost) {
        self.host = host
        endpointFile = OwnerEndpointFile(dataDirectory: host.settings.dataDirectory)
    }

    /// Starts serving `host` and its processing loop.
    static func start(_ host: LisaHost) async -> EmbeddedHostSession {
        let session = EmbeddedHostSession(host: host)
        await session.serve()
        session.runtime = Task.detached { await host.runtime.run() }
        return session
    }

    /// Stops the host in reverse order of start-up. Returns whether the data-directory lock was released: without a
    /// grace period it always is; with one, only when the processing loop finished within it.
    func shutdown(grace: Duration?) async -> Bool {
        if let server {
            await server.stop()
            self.server = nil
            ownerPort = nil
        }
        if wroteEndpoint {
            try? endpointFile.remove()
            wroteEndpoint = false
        }
        if let runtime {
            runtime.cancel()
            if let grace {
                guard await Self.finishes(runtime, within: grace) else { return false }
            } else {
                await runtime.value
            }
            self.runtime = nil
        }
        host.close()
        return true
    }

    // MARK: - Internals

    /// Serves the network API and writes the owner endpoint file, or records why it can't.
    private func serve() async {
        let started: (server: HostAPIServer, ownerCredential: String)
        do throws(HostError) {
            started = try await HostAPIServer.start(for: host)
        } catch {
            apiProblem = error.description
            return
        }
        let endpoint = OwnerEndpoint(
            port: started.server.ownerPort ?? 0, credential: started.ownerCredential,
            processID: ProcessInfo.processInfo.processIdentifier, issuedAt: Date())
        do {
            try endpointFile.write(endpoint)
        } catch {
            await started.server.stop()
            apiProblem = "the owner endpoint file could not be written: \(error)"
            return
        }
        server = started.server
        ownerPort = started.server.ownerPort
        wroteEndpoint = true
    }

    /// Whether `task` finishes within `grace`. Waiting on a task cannot be cancelled, so the first of the two waits to
    /// finish answers and the other is ignored.
    private static func finishes(_ task: Task<Void, Never>, within grace: Duration) async -> Bool {
        let answer = FirstAnswer()
        return await withCheckedContinuation { continuation in
            Task.detached {
                await task.value
                if answer.claim() { continuation.resume(returning: true) }
            }
            Task.detached {
                try? await Task.sleep(for: grace)
                if answer.claim() { continuation.resume(returning: false) }
            }
        }
    }
}

/// Lets exactly one of several racing waits resume a continuation.
private final class FirstAnswer: Sendable {
    private let answered = Mutex(false)

    /// `true` for the first caller only.
    func claim() -> Bool {
        answered.withLock { done in
            if done { return false }
            done = true
            return true
        }
    }
}
