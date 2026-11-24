// PROOF ONLY — Apps/Proof never ships. Frames over an established `NWConnection` (plan §8.7 connection behavior):
// each send awaited (backpressure) under a send timeout, a 30-second idle close on receive, and the frame header
// read and checked before the payload (TN3213: framing, flow control and timeouts are the app's job).

import Foundation
import LisaSyncProtocol
import Network

final class NWConnectionFrameChannel: ProofFrameChannel, @unchecked Sendable {
    static let sendTimeoutSeconds: Double = 10
    static let idleTimeoutSeconds: Double = 30

    let connection: NWConnection
    private let timerQueue = DispatchQueue(label: "org.example.lisa.proof.frame-timers")

    init(connection: NWConnection) {
        self.connection = connection
    }

    func send(_ frame: ProofFrame) async throws {
        try await sendRaw(frame.encoded())
    }

    func sendRaw(_ bytes: [UInt8]) async throws {
        let timeout = DispatchWorkItem { [connection] in connection.cancel() }
        timerQueue.asyncAfter(deadline: .now() + Self.sendTimeoutSeconds, execute: timeout)
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
        }
    }

    func receive() async throws -> ProofFrame {
        let idle = DispatchWorkItem { [connection] in connection.cancel() }
        timerQueue.asyncAfter(deadline: .now() + Self.idleTimeoutSeconds, execute: idle)
        defer { idle.cancel() }
        let bytes = try await receiveExactly(NearbyFrameHeader.length)
        let header: NearbyFrameHeader
        do {
            header = try NearbyFrameHeader.parse(bytes)
        } catch {
            throw ProofFrameError.header(error)
        }
        _ = try ProofFrame.kind(of: header)
        let payload = try await receiveExactly(header.payloadLength)
        return try ProofFrame.received(header, payload: payload)
    }

    func close() {
        connection.cancel()
    }

    /// Exactly `count` bytes; `count` was bounded by the header check, so the buffer never exceeds 1 MiB.
    private func receiveExactly(_ count: Int) async throws -> [UInt8] {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(count)
        while buffer.count < count {
            buffer += try await receiveChunk(maximum: count - buffer.count)
        }
        return buffer
    }

    private func receiveChunk(maximum: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], any Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content, !content.isEmpty {
                    continuation.resume(returning: Array(content))
                } else if isComplete {
                    continuation.resume(throwing: ProofChannelError.closedByPeer)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
