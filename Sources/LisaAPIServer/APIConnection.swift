// Serves one connection: assembles each request, answers expectations and rejections, calls the request handler and
// writes the response, one request at a time, until the client or the server ends the connection.

import LisaAPIContract
import NIOCore
import NIOHTTP1

/// The request loop of one connection.
struct APIConnection {
    let peer: APIPeer
    let limits: APIServerLimits
    let handler: APIRequestHandler

    func serve(
        inbound: NIOAsyncChannelInboundStream<HTTPServerRequestPart>,
        outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws {
        var assembler = RequestAssembler(maxBodyBytes: limits.maxBodyBytes, maxDiscardBytes: limits.maxDiscardBytes)
        var parts = inbound.makeAsyncIterator()
        while let part = try await parts.next() {
            switch assembler.consume(part) {
            case .needMore:
                continue
            case .sendContinue:
                try await outbound.write(.head(HTTPResponseHead(version: .http1_1, status: .continue)))
            case .reject(let rejection, let version, let drain):
                try await write(rejection.response, version: version, keepAlive: false, to: outbound)
                if drain { try await discardBody(&parts) }
                return
            case .complete(let head, let body):
                let request: APIRequest
                do {
                    request = try HTTPTranslation.request(head: head, body: body)
                } catch {
                    try await write(error.response, version: head.version, keepAlive: false, to: outbound)
                    return
                }
                let response = await handler(request, peer)
                try await write(response, version: head.version, keepAlive: head.isKeepAlive, to: outbound)
                guard head.isKeepAlive else { return }
            }
        }
    }

    private func write(
        _ response: APIResponse, version: HTTPVersion, keepAlive: Bool,
        to outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>
    ) async throws {
        let (head, body) = HTTPTranslation.responseParts(response, version: version, keepAlive: keepAlive)
        try await outbound.write(contentsOf: [.head(head), .body(.byteBuffer(body)), .end(nil)])
    }

    /// Reads and drops the rest of a rejected request's body, up to the discard limit.
    private func discardBody(_ parts: inout NIOAsyncChannelInboundStream<HTTPServerRequestPart>.AsyncIterator)
        async throws
    {
        var discarded = 0
        while let part = try await parts.next() {
            guard case .body(let chunk) = part else { return }
            discarded += chunk.readableBytes
            if discarded > limits.maxDiscardBytes { return }
        }
    }
}
