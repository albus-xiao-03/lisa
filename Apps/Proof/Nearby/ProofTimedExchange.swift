// PROOF ONLY — Apps/Proof never ships. What runs after authentication (plan §10.5 N-1, §10.8 timing): the device
// whose harness role is "sender" drives 100 echo frames timed as round trips on its own monotonic clock, one frame
// at the full 1 MiB budget, and 20 four-timestamp clock exchanges; the "receiver" echoes. An oversize header, if the
// owner injects one, must be refused by the receiver before anything is allocated.

import LisaSyncProtocol

struct ProofTimedExchange: Sendable {
    static let frameCount = 100

    struct DriverReport: Codable, Sendable {
        let frames: Int
        let payloadBytes: Int
        let roundTripsNanoseconds: [UInt64]
        let minimumNanoseconds: UInt64
        let medianNanoseconds: UInt64
        let p95Nanoseconds: UInt64
        let maximumNanoseconds: UInt64
        let fullBudgetFrameRoundTripNanoseconds: UInt64
        let clockSamples: [ProofClockSample]
        let clockOffsetNanoseconds: Int64?
        let clockDelayNanoseconds: Int64?
        let oversizeHeaderSent: Bool
        let peerClosedAfterOversize: Bool?
    }

    struct EchoReport: Codable, Sendable {
        let framesEchoed: Int
        let clockReplies: Int
        /// "done", "oversize-header-refused-before-allocation", "peer-closed" or "error: …".
        let endedBy: String
    }

    func drive(on channel: some ProofFrameChannel, payloadBytes: Int, sendOversizeHeader: Bool) async throws
        -> DriverReport
    {
        let size = min(max(payloadBytes, 8), ProofFrame.maximumPayload)
        var roundTrips: [UInt64] = []
        for index in 0..<Self.frameCount {
            roundTrips.append(try await echo(index: UInt64(index), size: size, on: channel))
        }
        let fullBudget = try await echo(index: UInt64.max, size: ProofFrame.maximumPayload, on: channel)
        var samples: [ProofClockSample] = []
        for _ in 0..<ProofClockOffset.exchanges {
            let t1 = ProofMonotonicClock.nowNanoseconds()
            try await channel.send(try ProofFrame.make(.clockRequest, Self.bytes(t1)))
            let reply = try await channel.receive()
            let t4 = ProofMonotonicClock.nowNanoseconds()
            guard reply.kind == .clockReply, reply.payload.count == 24, Self.value(reply.payload, at: 0) == t1 else {
                throw ProofSessionRefusal.unexpectedFrame(reply.kind.rawValue)
            }
            samples.append(
                ProofClockSample(
                    t1: t1, t2: Self.value(reply.payload, at: 8), t3: Self.value(reply.payload, at: 16), t4: t4))
        }
        var peerClosed: Bool?
        if sendOversizeHeader {
            try await channel.sendRaw(ProofFrame.oversizeHeaderBytes(kind: .echoRequest))
            do {
                _ = try await channel.receive()
                peerClosed = false
            } catch {
                peerClosed = true
            }
        } else {
            try await channel.send(try ProofFrame.make(.done, []))
        }
        let sorted = roundTrips.sorted()
        let estimate = ProofClockOffset.estimate(samples)
        return DriverReport(
            frames: Self.frameCount, payloadBytes: size, roundTripsNanoseconds: roundTrips,
            minimumNanoseconds: sorted.first ?? 0, medianNanoseconds: sorted[sorted.count / 2],
            p95Nanoseconds: sorted[min(sorted.count - 1, sorted.count * 95 / 100)],
            maximumNanoseconds: sorted.last ?? 0, fullBudgetFrameRoundTripNanoseconds: fullBudget,
            clockSamples: samples, clockOffsetNanoseconds: estimate?.offsetNanoseconds,
            clockDelayNanoseconds: estimate?.delayNanoseconds, oversizeHeaderSent: sendOversizeHeader,
            peerClosedAfterOversize: peerClosed)
    }

    /// The receiver's loop. It never allocates for a header over the budget: `receive()` refuses it first.
    func echo(on channel: some ProofFrameChannel) async -> EchoReport {
        var echoed = 0
        var clockReplies = 0
        while true {
            do {
                let frame = try await channel.receive()
                switch frame.kind {
                case .echoRequest:
                    try await channel.send(try ProofFrame.make(.echoReply, frame.payload))
                    echoed += 1
                case .clockRequest:
                    let t2 = ProofMonotonicClock.nowNanoseconds()
                    let t1 = frame.payload.count == 8 ? Self.value(frame.payload, at: 0) : 0
                    let t3 = ProofMonotonicClock.nowNanoseconds()
                    try await channel.send(
                        try ProofFrame.make(.clockReply, Self.bytes(t1) + Self.bytes(t2) + Self.bytes(t3)))
                    clockReplies += 1
                case .done:
                    return EchoReport(framesEchoed: echoed, clockReplies: clockReplies, endedBy: "done")
                default:
                    channel.close()
                    return EchoReport(
                        framesEchoed: echoed, clockReplies: clockReplies,
                        endedBy: "error: \(ProofSessionRefusal.roleConflict.code) (frame \(frame.kind.rawValue))")
                }
            } catch ProofFrameError.header(.budget) {
                channel.close()
                return EchoReport(
                    framesEchoed: echoed, clockReplies: clockReplies,
                    endedBy: "oversize-header-refused-before-allocation")
            } catch ProofChannelError.closedByPeer {
                return EchoReport(framesEchoed: echoed, clockReplies: clockReplies, endedBy: "peer-closed")
            } catch {
                channel.close()
                return EchoReport(framesEchoed: echoed, clockReplies: clockReplies, endedBy: "error: \(error)")
            }
        }
    }

    private func echo(index: UInt64, size: Int, on channel: some ProofFrameChannel) async throws -> UInt64 {
        var payload = [UInt8](repeating: 0xA5, count: size)
        payload.replaceSubrange(0..<8, with: Self.bytes(index))
        let start = ProofMonotonicClock.nowNanoseconds()
        try await channel.send(try ProofFrame.make(.echoRequest, payload))
        let reply = try await channel.receive()
        let end = ProofMonotonicClock.nowNanoseconds()
        if reply.kind == .echoRequest { throw ProofSessionRefusal.roleConflict }
        guard reply.kind == .echoReply, reply.payload == payload else {
            throw ProofSessionRefusal.unexpectedFrame(reply.kind.rawValue)
        }
        return end - start
    }

    static func bytes(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8(truncatingIfNeeded: value >> (56 - 8 * UInt64($0))) }
    }

    static func value(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        bytes[offset..<(offset + 8)].reduce(0) { $0 << 8 | UInt64($1) }
    }
}
