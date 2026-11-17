// Answers requests the HTTP parser refuses. It replaces NIO's default error handler, which answers every parser error
// with 400: oversized header fields get 431 (RFC 6585 §5, RFC 9110 §5.4), anything else 400, and the parser then
// closes the connection. Smuggling attempts (Content-Length with Transfer-Encoding, repeated lengths) land here too.

import NIOCore
import NIOHTTP1

/// Writes the error response for a parser failure, unless a response is already under way.
final class ParserErrorResponder: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPServerRequestPart
    typealias OutboundIn = HTTPServerResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    private var responseInProgress = false

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        guard let parserError = error as? HTTPParserError else {
            context.fireErrorCaught(error)
            return
        }
        if !responseInProgress {
            let rejection: ServerRejection
            if case .headerOverflow = parserError {
                rejection = .headersTooLarge
            } else {
                rejection = .malformed
            }
            let (head, body) = HTTPTranslation.responseParts(rejection.response, version: .http1_1, keepAlive: false)
            context.write(wrapOutboundOut(.head(head)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        context.fireErrorCaught(error)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch unwrapOutboundIn(data) {
        case .head(let head) where (100..<200).contains(head.status.code):
            break
        case .head:
            responseInProgress = true
        case .body:
            break
        case .end:
            responseInProgress = false
        }
        context.write(data, promise: promise)
    }
}
