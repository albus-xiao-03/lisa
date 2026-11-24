// One HTTP exchange with the controlled provider-shaped server (plan §10.8): APNs (`POST /3/device/<token>`), OpenAI
// (`/v1/chat/completions`, `/v1/responses`), Anthropic (`/v1/messages`), Ollama (`/api/chat`) and Twilio
// (`POST /2010-04-01/Accounts/<sid>/Calls.json`) submissions, keyed by the `Lisa-Operation-ID` header the harness
// sends; identity, mailbox and calendar reads answered empty and classified; and the lookup
// `GET /_controlled/lookup?key=<k>`. One request per connection.

import Foundation
import NIOCore
import NIOHTTP1

struct ControlledHTTPSession {
    static let maximumBodyBytes = 1_048_576
    let registry: ControlledRegistry

    func serve(_ connection: NIOAsyncChannel<HTTPServerRequestPart, HTTPServerResponsePart>) async {
        do {
            try await connection.executeThenClose { inbound, outbound in
                var head: HTTPRequestHead?
                var body = 0
                for try await part in inbound {
                    switch part {
                    case .head(let value): head = value
                    case .body(let buffer):
                        body += buffer.readableBytes
                        if body > Self.maximumBodyBytes {
                            try await respond(outbound, .payloadTooLarge, "{\"error\":\"too large\"}")
                            return
                        }
                    case .end:
                        guard let head else { return }
                        try await handle(head, outbound)
                        return
                    }
                }
            }
        } catch {
            // The client went away; nothing to record.
        }
    }

    private func handle(_ head: HTTPRequestHead, _ outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>)
        async throws
    {
        let method = head.method.rawValue
        let requestClass = ControlledRequestClass.classify(method: method, path: head.uri)
        registry.classify(requestClass)
        switch requestClass {
        case .control:
            try await lookup(head.uri, outbound)
        case .send, .modelRequest, .call:
            guard let key = head.headers.first(name: "Lisa-Operation-ID"), !key.isEmpty else {
                try await respond(outbound, .badRequest, "{\"error\":\"Lisa-Operation-ID missing\"}")
                return
            }
            let prefix =
                switch requestClass {
                case .call: "CA"
                case .modelRequest: "req_"
                default: "apns-"
                }
            switch registry.admit(key: key, referencePrefix: prefix) {
            case .answer(let reference):
                let status: HTTPResponseStatus = requestClass == .call ? .created : .ok
                try await respond(outbound, status, "{\"id\":\"\(reference)\"}", reference: reference)
            case .drop:
                return
            case .rateLimited:
                try await respond(outbound, .tooManyRequests, "{\"error\":\"rate limited\"}", retryAfter: "1")
            }
        case .identityOnly, .mailboxRead, .calendarRead, .other:
            try await respond(outbound, .ok, "{}")
        }
    }

    private func lookup(_ uri: String, _ outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>) async throws {
        let components = URLComponents(string: uri)
        guard components?.path == "/_controlled/lookup",
            let key = components?.queryItems?.first(where: { $0.name == "key" })?.value
        else {
            try await respond(outbound, .notFound, "{\"error\":\"no such control\"}")
            return
        }
        switch registry.lookup(key: key) {
        case .disabled: try await respond(outbound, .serviceUnavailable, "{\"lookup\":\"disabled\"}")
        case .notFound: try await respond(outbound, .notFound, "{\"found\":false}")
        case .found(let reference, let count):
            try await respond(outbound, .ok, "{\"count\":\(count),\"found\":true,\"reference\":\"\(reference)\"}")
        }
    }

    private func respond(
        _ outbound: NIOAsyncChannelOutboundWriter<HTTPServerResponsePart>, _ status: HTTPResponseStatus, _ json: String,
        reference: String? = nil, retryAfter: String? = nil
    ) async throws {
        var headers = HTTPHeaders([("Content-Type", "application/json"), ("Connection", "close")])
        headers.add(name: "Content-Length", value: String(json.utf8.count))
        if let reference { headers.add(name: "Lisa-Reference", value: reference) }
        if let retryAfter { headers.add(name: "Retry-After", value: retryAfter) }
        try await outbound.write(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers)))
        try await outbound.write(.body(.byteBuffer(ByteBuffer(string: json))))
        try await outbound.write(.end(nil))
    }
}
