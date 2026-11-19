// The server limits expressed as NIO's HTTP decoder limits; the request line counts toward the header limit.

import NIOHTTP1

extension APIServerLimits {
    var decoderLimits: NIOHTTPDecoderLimitConfiguration {
        var limits = NIOHTTPDecoderLimitConfiguration()
        limits.maxHeaderFieldSize = maxHeaderBytes
        limits.maxHeaderListSize = maxHeaderBytes
        limits.maxHeaderFieldCount = maxHeaderFields
        return limits
    }
}
