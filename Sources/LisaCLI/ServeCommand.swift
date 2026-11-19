// `lisa serve` (CLI-01): runs the host until SIGINT or SIGTERM — the processing loop and the network API, with a
// loopback owner listener that other `lisa` commands use as clients. Shutdown is graceful: no new connections,
// requests in progress finish, the current cycle completes, then the data-directory lock is released.

import ArgumentParser
import Foundation
import LisaAPIServer
import LisaClient
import LisaHost
import LisaRuntime

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the host runtime and the network API until interrupted.",
        discussion: """
            Serves the API on the configured api.bindAddress and api.port (loopback by default). Other lisa \
            commands run meanwhile connect to this host as clients. Stop with Ctrl-C or SIGTERM.
            """)

    @OptionGroup var host: HostOptions

    struct Listening: Encodable {
        var role: String
        var address: String
        var port: Int
        var transport: String
    }

    struct Summary: Encodable {
        var state: String
        var listeners: [Listening]
        var recovery: [String]
    }

    func run() async throws {
        let signals = TerminationSignals.stream()
        let lisa = try HostSession.open(host, mode: "serve", logToStandardError: true)
        defer { lisa.close() }
        let started: (server: HostAPIServer, ownerCredential: String)
        do {
            started = try await HostAPIServer.start(for: lisa)
        } catch {
            Output.error(error.description)
            throw LisaExit.hostRefused
        }
        let endpointFile = OwnerEndpointFile(dataDirectory: lisa.settings.dataDirectory)
        do {
            try endpointFile.write(
                OwnerEndpoint(
                    port: started.server.ownerPort ?? 0, credential: started.ownerCredential, processID: getpid(),
                    issuedAt: Date()))
        } catch {
            await started.server.stop()
            Output.error("the owner endpoint file could not be written: \(error)")
            throw LisaExit.failure
        }
        let summary = Summary(
            state: "serving",
            listeners: started.server.listeners.map {
                Listening(role: $0.role.rawValue, address: $0.address, port: $0.port, transport: $0.transport)
            },
            recovery: lisa.recoveryNotes)
        try host.output.emit(summary) { summary in
            (summary.listeners.map { "listening (\($0.role)): \($0.address):\($0.port) \($0.transport)" }
                + summary.recovery.map { "recovery: \($0)" }).joined(separator: "\n")
        }
        // A supervisor reading standard output must see the listeners now, not when the host exits.
        fflush(nil)
        let runtime = Task { await lisa.runtime.run() }
        for await _ in signals { break }
        // Reverse order of start-up (plan §5.2): the network server, then the runtime, then the lock.
        await started.server.stop()
        try? endpointFile.remove()
        runtime.cancel()
        await runtime.value
    }
}
