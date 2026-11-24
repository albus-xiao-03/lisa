// PROOF ONLY — Apps/Proof never ships, and this is not LisaHTTP1 (M7). The probe's minimal HTTP/1.1 GET on an
// already-checked connection (plan §8.9.3 check 5 in miniature): one request, `Accept-Encoding: identity`,
// `Connection: close`, no cookies or caching; the status, the Location header and a bounded body digest are read.

import Foundation
import LisaCrypto
import Network

struct ProbeHTTPResponse: Codable, Sendable {
    let status: Int
    let location: String?
    let headerBytes: Int
    let bodyBytesRead: Int
    let bodySHA256: String
    let truncated: Bool
}

enum ProbeHTTP1Exchange {
    static let headerLimit = 32_768
    static let bodyLimit = 262_144

    enum Failure: Error {
        case headerTooLarge, malformedStatusLine, closedBeforeHeaders
    }

    static func get(on connection: NWConnection, host: String, port: UInt16, pathAndQuery: String) async throws
        -> ProbeHTTPResponse
    {
        var authority = host.contains(":") ? "[\(host)]" : host
        if port != 443 { authority += ":\(port)" }
        let request =
            "GET \(pathAndQuery) HTTP/1.1\r\nHost: \(authority)\r\nAccept-Encoding: identity\r\n"
            + "Connection: close\r\nUser-Agent: LisaProof/1 (proof-only)\r\n\r\n"
        try await send(Data(request.utf8), on: connection)
        var buffer: [UInt8] = []
        var headerEnd: Int?
        var complete = false
        while headerEnd == nil {
            guard !complete else { throw Failure.closedBeforeHeaders }
            let (chunk, done) = try await receive(on: connection)
            buffer += chunk
            complete = done
            headerEnd = find([13, 10, 13, 10], in: buffer)
            if headerEnd == nil, buffer.count > headerLimit { throw Failure.headerTooLarge }
        }
        let headerCount = headerEnd! + 4
        let lines = String(decoding: buffer.prefix(headerEnd!), as: UTF8.self).components(separatedBy: "\r\n")
        let statusParts = lines.first?.split(separator: " ", maxSplits: 2) ?? []
        guard statusParts.count >= 2, statusParts[0].hasPrefix("HTTP/1."), let status = Int(statusParts[1]) else {
            throw Failure.malformedStatusLine
        }
        let location = lines.dropFirst().first { $0.lowercased().hasPrefix("location:") }
            .map { String($0.dropFirst("location:".count)).trimmingCharacters(in: .whitespaces) }
        var body = Array(buffer.dropFirst(headerCount))
        while !complete, body.count <= bodyLimit {
            let (chunk, done) = try await receive(on: connection)
            body += chunk
            complete = done
        }
        let truncated = body.count > bodyLimit
        let kept = Array(body.prefix(bodyLimit))
        return ProbeHTTPResponse(
            status: status, location: location, headerBytes: headerCount, bodyBytesRead: kept.count,
            bodySHA256: Digests.sha256Hex(Data(kept)), truncated: truncated)
    }

    private static func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
        }
    }

    private static func receive(on connection: NWConnection) async throws -> ([UInt8], Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<([UInt8], Bool), any Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (content.map { Array($0) } ?? [], isComplete))
                }
            }
        }
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        return (0...(haystack.count - needle.count)).first { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
