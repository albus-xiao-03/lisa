// The host API's network server (API-01): NIO HTTP/1.1 on the configured listeners, one request at a time per
// connection, and a graceful shutdown that lets requests in progress finish (ChannelShouldQuiesceEvent).

import LisaAPIContract
import LisaLogging
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL
import Synchronization

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

/// Serves the API until `shutdown()`. Plain HTTP is accepted only on loopback addresses; other listeners need native
/// TLS or a trusted reverse proxy, and the owner listener is always plain loopback.
public final class APIServer: Sendable {
    typealias Connection = NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>
    typealias Listener = NIOAsyncChannel<Connection, Never>

    let listeners: [APIListenerConfiguration]
    let limits: APIServerLimits
    let handler: APIRequestHandler
    let logger: Logger
    let group: MultiThreadedEventLoopGroup
    private let state = Mutex(State())

    enum Phase {
        case idle, starting, running, stopping, stopped
    }

    struct State {
        var phase = Phase.idle
        var listenerChannels: [any Channel] = []
        var connections: [ObjectIdentifier: any Channel] = [:]
        var serving: Task<Void, Never>?
    }

    public init(
        listeners: [APIListenerConfiguration], limits: APIServerLimits = APIServerLimits(),
        logger: Logger, group: MultiThreadedEventLoopGroup = .singleton, handler: @escaping APIRequestHandler
    ) {
        self.listeners = listeners
        self.limits = limits
        self.logger = logger
        self.group = group
        self.handler = handler
    }

    /// Binds every listener and starts serving. If any listener fails, none stays open.
    public func start() async throws(APIServerError) -> [BoundAPIListener] {
        let startable = state.withLock { state in
            guard state.phase == .idle else { return false }
            state.phase = .starting
            return true
        }
        guard startable else { throw .notStartable }
        var bound: [(Listener, APIListenerConfiguration)] = []
        var result: [BoundAPIListener] = []
        do {
            if let problem = limits.problems.first { throw APIServerError.invalidConfiguration(problem) }
            if listeners.isEmpty { throw APIServerError.invalidConfiguration("no listener is configured") }
            for listener in listeners {
                try Self.validate(listener)
                let channel: Listener
                do {
                    channel = try await bind(listener)
                } catch {
                    throw Self.bindError(error, listener)
                }
                bound.append((channel, listener))
                result.append(
                    BoundAPIListener(
                        role: listener.role, address: listener.address,
                        port: channel.channel.localAddress?.port ?? listener.port, transport: listener.transport.name))
            }
        } catch {
            for (channel, _) in bound { try? await channel.channel.close().get() }
            state.withLock { $0.phase = .stopped }
            throw (error as? APIServerError) ?? .invalidConfiguration("the listeners could not be opened")
        }
        let listening = bound
        state.withLock { state in
            state.phase = .running
            state.listenerChannels = listening.map { $0.0.channel }
        }
        let serving = Task { [self] in
            await withDiscardingTaskGroup { group in
                for (channel, listener) in listening {
                    group.addTask { await self.accept(on: channel, listener) }
                }
            }
        }
        state.withLock { $0.serving = serving }
        for listener in result {
            logger.notice(
                "api listening",
                [
                    "role": .public(listener.role.rawValue), "address": .public(listener.address),
                    "port": .count(listener.port), "transport": .public(listener.transport),
                ])
        }
        return result
    }

    /// Stops accepting connections, lets requests in progress finish within the grace period, then closes every
    /// connection. Calling it again, or before `start()`, does nothing.
    public func shutdown() async {
        let (listenerChannels, serving) = state.withLock { state -> ([any Channel], Task<Void, Never>?) in
            guard state.phase == .running else { return ([], nil) }
            state.phase = .stopping
            return (state.listenerChannels, state.serving)
        }
        guard let serving else { return }
        for channel in listenerChannels { try? await channel.close().get() }
        for channel in state.withLock({ Array($0.connections.values) }) {
            channel.pipeline.fireUserInboundEventTriggered(ChannelShouldQuiesceEvent())
        }
        let deadline = ContinuousClock.now + limits.shutdownGracePeriod
        while ContinuousClock.now < deadline && !state.withLock({ $0.connections.isEmpty }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        for channel in state.withLock({ Array($0.connections.values) }) { try? await channel.close().get() }
        await serving.value
        state.withLock { state in
            state.phase = .stopped
            state.listenerChannels = []
            state.serving = nil
        }
        logger.notice("api server stopped", [:])
    }

    /// Connections currently served.
    public var connectionCount: Int { state.withLock { $0.connections.count } }

    // MARK: - Listening

    private func bind(_ listener: APIListenerConfiguration) async throws -> Listener {
        let address = try SocketAddress(ipAddress: listener.address, port: listener.port)
        let tls: NIOSSLContext? =
            if case .tls(let identity) = listener.transport { identity.context } else { nil }
        let decoderLimits = limits.decoderLimits
        let timeouts = ConnectionDeadlineHandler.Timeouts(
            firstRequest: TimeAmount(limits.firstRequestTimeout), keepAlive: TimeAmount(limits.keepAliveTimeout),
            body: TimeAmount(limits.bodyTimeout))
        return try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .serverChannelOption(.backlog, value: 128)
            .bind(to: address) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let pipeline = channel.pipeline.syncOperations
                    if let tls { try pipeline.addHandler(NIOSSLServerHandler(context: tls)) }
                    try pipeline.configureHTTPServerPipeline(
                        withPipeliningAssistance: true, withErrorHandling: false, withOutboundHeaderValidation: true,
                        withEncoderConfiguration: HTTPResponseEncoder.Configuration(),
                        withDecoderLimitConfiguration: decoderLimits)
                    try pipeline.addHandler(ParserErrorResponder())
                    try pipeline.addHandler(ConnectionDeadlineHandler(timeouts: timeouts))
                    return try Connection(wrappingChannelSynchronously: channel)
                }
            }
    }

    private func accept(on listener: Listener, _ configuration: APIListenerConfiguration) async {
        do {
            try await withThrowingDiscardingTaskGroup { group in
                try await listener.executeThenClose { connections in
                    for try await connection in connections {
                        group.addTask { await self.serve(connection, configuration) }
                    }
                }
            }
        } catch {
            if state.withLock({ $0.phase == .running }) {
                logger.warning(
                    "api listener failed",
                    ["role": .public(configuration.role.rawValue), "error": .public(Self.errorClass(error))])
            }
        }
    }

    private func serve(_ connection: Connection, _ configuration: APIListenerConfiguration) async {
        let channel = connection.channel
        let key = ObjectIdentifier(channel)
        let admitted = state.withLock { state in
            guard state.phase == .running, state.connections.count < limits.maxConnections else { return false }
            state.connections[key] = channel
            return true
        }
        guard admitted else {
            try? await channel.close().get()
            return
        }
        defer { _ = state.withLock { $0.connections.removeValue(forKey: key) } }
        let peer = APIPeer(
            listener: configuration.role,
            isLocal: configuration.peersMayBeLocal && PeerAddress.isLoopback(channel.remoteAddress))
        let session = APIConnection(peer: peer, limits: limits, handler: handler)
        do {
            try await connection.executeThenClose { inbound, outbound in
                try await session.serve(inbound: inbound, outbound: outbound)
            }
        } catch {
            logger.debug("api connection ended", ["error": .public(Self.errorClass(error))])
        }
    }

    // MARK: - Validation and errors

    /// Plain HTTP only on loopback (API-01); the owner listener only as plain loopback.
    static func validate(_ listener: APIListenerConfiguration) throws(APIServerError) {
        guard let loopback = PeerAddress.isLoopbackLiteral(listener.address) else {
            throw .invalidConfiguration("\(listener.address) is not an IP address")
        }
        guard (0...65_535).contains(listener.port) else {
            throw .invalidConfiguration("port \(listener.port) is out of range")
        }
        switch (listener.role, listener.transport) {
        case (.owner, .plain):
            if !loopback { throw .invalidConfiguration("the owner listener must use a loopback address") }
        case (.owner, _):
            throw .invalidConfiguration("the owner listener must be plain HTTP on a loopback address")
        case (.devices, .plain):
            if !loopback {
                throw .invalidConfiguration(
                    "plain HTTP is allowed only on a loopback address; use native TLS or a trusted reverse proxy")
            }
        case (.devices, .reverseProxy), (.devices, .tls):
            break
        }
    }

    static func bindError(_ error: any Error, _ listener: APIListenerConfiguration) -> APIServerError {
        if let error = error as? APIServerError { return error }
        if let error = error as? IOError, error.errnoCode == EADDRINUSE {
            return .addressInUse(address: listener.address, port: listener.port)
        }
        if error is SocketAddressError { return .invalidConfiguration("\(listener.address) is not an IP address") }
        return .bindFailed(address: listener.address, port: listener.port, reason: errorClass(error))
    }

    /// The kind of an error, safe to log: a type name and, for system errors, the error number.
    static func errorClass(_ error: any Error) -> String {
        if let error = error as? IOError { return "IOError(errno \(error.errnoCode))" }
        return String(describing: type(of: error))
    }
}
