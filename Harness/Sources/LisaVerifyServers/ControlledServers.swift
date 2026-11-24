// The harness's controlled servers (plan §10.8 `Sources/LisaVerifyServers/`): an SMTP listener and an HTTP listener in
// the shapes of the providers Lisa uses, on the loopback interface, sharing one counting registry. Labeled
// controlled; they never contact a service and are never a stand-in for a live or physical case.

import NIOCore
import NIOHTTP1
import NIOPosix

/// A running set of controlled servers.
public final class ControlledServers: Sendable {
    public let registry: ControlledRegistry
    public let smtpPort: Int
    public let httpPort: Int
    private let smtp: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>
    private let http: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>, Never>

    private init(
        registry: ControlledRegistry, smtp: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>,
        http: NIOAsyncChannel<NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>, Never>
    ) {
        self.registry = registry
        self.smtp = smtp
        self.http = http
        smtpPort = smtp.channel.localAddress?.port ?? 0
        httpPort = http.channel.localAddress?.port ?? 0
    }

    /// Starts both listeners on 127.0.0.1 with ports the system chooses.
    public static func start(registry: ControlledRegistry = ControlledRegistry()) async throws -> ControlledServers {
        let group = MultiThreadedEventLoopGroup.singleton
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let smtp = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(to: address) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }
        let http = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(to: address) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                    return try NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>(
                        wrappingChannelSynchronously: channel)
                }
            }
        let servers = ControlledServers(registry: registry, smtp: smtp, http: http)
        Task {
            try? await smtp.executeThenClose { connections in
                try await withThrowingDiscardingTaskGroup { group in
                    for try await connection in connections {
                        group.addTask { await ControlledSMTPSession(registry: registry).serve(connection) }
                    }
                }
            }
        }
        Task {
            try? await http.executeThenClose { connections in
                try await withThrowingDiscardingTaskGroup { group in
                    for try await connection in connections {
                        group.addTask { await ControlledHTTPSession(registry: registry).serve(connection) }
                    }
                }
            }
        }
        return servers
    }

    /// Closes both listeners.
    public func stop() async {
        try? await smtp.channel.close()
        try? await http.channel.close()
    }
}
