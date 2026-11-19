// Assembles one request at a time from NIO's head, body and end parts. NIO enforces no body limit and does not answer
// `Expect: 100-continue`, so both happen here (RFC 9110 §10.1.1, §15.5.14).

import NIOCore
import NIOHTTP1

/// The request being received on one connection.
struct RequestAssembler {
    /// What the connection does next.
    enum Step {
        /// Wait for the next part.
        case needMore
        /// Send `100 (Continue)` now; the client waits for it before sending the body.
        case sendContinue
        /// The request is complete.
        case complete(HTTPRequestHead, ByteBuffer?)
        /// Answer with the rejection and close. With `drain`, first read and discard the rest of the body (within the
        /// discard limit) so the client sees the answer rather than a reset.
        case reject(ServerRejection, version: HTTPVersion, drain: Bool)
    }

    let maxBodyBytes: Int
    let maxDiscardBytes: Int
    private var head: HTTPRequestHead?
    private var body: ByteBuffer?

    init(maxBodyBytes: Int, maxDiscardBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
        self.maxDiscardBytes = maxDiscardBytes
    }

    mutating func consume(_ part: HTTPServerRequestPart) -> Step {
        switch part {
        case .head(let head):
            return begin(head)
        case .body(var chunk):
            guard let head else { return .reject(.malformed, version: .http1_1, drain: false) }
            let received = (body?.readableBytes ?? 0) + chunk.readableBytes
            guard received <= maxBodyBytes else {
                return .reject(.payloadTooLarge(limit: maxBodyBytes), version: head.version, drain: true)
            }
            if body == nil {
                body = chunk
            } else {
                body?.writeBuffer(&chunk)
            }
            return .needMore
        case .end:
            guard let head else { return .reject(.malformed, version: .http1_1, drain: false) }
            let complete = Step.complete(head, body)
            self.head = nil
            body = nil
            return complete
        }
    }

    private mutating func begin(_ head: HTTPRequestHead) -> Step {
        self.head = head
        body = nil
        // The parser has already refused malformed or conflicting lengths.
        let declared = head.headers["content-length"].first.flatMap { Int($0) }
        let chunked = head.headers["transfer-encoding"].contains { $0.lowercased().contains("chunked") }
        let expectations = head.headers["expect"]
        // An HTTP/1.0 expectation is ignored (RFC 9110 §10.1.1).
        let expectsContinue = head.version != .http1_0 && !expectations.isEmpty
        if expectsContinue && (expectations.count != 1 || expectations[0].lowercased() != "100-continue") {
            return .reject(.expectationFailed, version: head.version, drain: false)
        }
        if let declared, declared > maxBodyBytes {
            // A client waiting for 100 (Continue) has sent nothing to discard.
            let drain = !expectsContinue && declared - maxBodyBytes <= maxDiscardBytes
            return .reject(.payloadTooLarge(limit: maxBodyBytes), version: head.version, drain: drain)
        }
        if expectsContinue && (chunked || (declared ?? 0) > 0) { return .sendContinue }
        return .needMore
    }
}
