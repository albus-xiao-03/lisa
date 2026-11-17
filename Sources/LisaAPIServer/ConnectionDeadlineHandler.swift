// Closes connections that are too slow or idle. NIO has no request or handshake timeouts of its own, so: the first
// request head must arrive in time (which also bounds a TLS handshake), each body must finish in time, and a kept-alive
// connection must start its next request in time. Nothing is timed while the host is producing a response.

import NIOCore
import NIOHTTP1

/// One timer per connection, re-armed as requests and responses pass.
final class ConnectionDeadlineHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPServerRequestPart
    typealias OutboundIn = HTTPServerResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    struct Timeouts {
        var firstRequest: TimeAmount
        var keepAlive: TimeAmount
        var body: TimeAmount
    }

    private let timeouts: Timeouts
    private var timer: Scheduled<Void>?

    init(timeouts: Timeouts) {
        self.timeouts = timeouts
    }

    func handlerAdded(context: ChannelHandlerContext) {
        if context.channel.isActive { arm(context, timeouts.firstRequest) }
    }

    func channelActive(context: ChannelHandlerContext) {
        if timer == nil { arm(context, timeouts.firstRequest) }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head: arm(context, timeouts.body)
        case .body: break
        case .end: cancel()
        }
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if case .end = unwrapOutboundIn(data) { arm(context, timeouts.keepAlive) }
        context.write(data, promise: promise)
    }

    func channelInactive(context: ChannelHandlerContext) {
        cancel()
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        cancel()
    }

    private func arm(_ context: ChannelHandlerContext, _ amount: TimeAmount) {
        cancel()
        timer = context.eventLoop.assumeIsolated().scheduleTask(in: amount) {
            context.close(promise: nil)
        }
    }

    private func cancel() {
        timer?.cancel()
        timer = nil
    }
}
