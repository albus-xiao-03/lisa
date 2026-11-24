// PROOF ONLY — Apps/Proof never ships. The proof's nearby frames (plan §8.16.2, §8.7): LisaSyncProtocol's 8-byte
// `NearbyFrameHeader`, which enforces the 1 MiB budget from the header before anything is allocated, and the proof's
// own registry of frame kinds (the production registry belongs to the M6 session layer).

import LisaSyncProtocol

enum ProofFrameKind: UInt8, Sendable, CaseIterable {
    case hello = 1
    case authentication = 2
    case verdict = 3
    case echoRequest = 4
    case echoReply = 5
    case clockRequest = 6
    case clockReply = 7
    case discoverySecret = 8
    case done = 9
}

enum ProofFrameError: Error, Equatable, Sendable {
    /// The header was refused (length, budget, version or reserved bytes) before the payload was read.
    case header(NearbyFrameError)
    case unknownKind(UInt8)
    case payloadLength(expected: Int, actual: Int)
}

struct ProofFrame: Sendable {
    /// The largest payload: 1 MiB minus the header.
    static let maximumPayload = NearbyFrameHeader.maximumPayloadBytes

    let kind: ProofFrameKind
    let payload: [UInt8]
    let header: NearbyFrameHeader

    private init(kind: ProofFrameKind, payload: [UInt8], header: NearbyFrameHeader) {
        self.kind = kind
        self.payload = payload
        self.header = header
    }

    /// A frame within the budget.
    static func make(_ kind: ProofFrameKind, _ payload: [UInt8]) throws(ProofFrameError) -> ProofFrame {
        do {
            let header = try NearbyFrameHeader(kind: kind.rawValue, payloadLength: payload.count)
            return ProofFrame(kind: kind, payload: payload, header: header)
        } catch {
            throw .header(error)
        }
    }

    /// The kind a received header names; an unknown kind is refused before the payload is read.
    static func kind(of header: NearbyFrameHeader) throws(ProofFrameError) -> ProofFrameKind {
        guard let kind = ProofFrameKind(rawValue: header.kind) else { throw .unknownKind(header.kind) }
        return kind
    }

    /// A received frame: its checked header and exactly the payload that header announced.
    static func received(_ header: NearbyFrameHeader, payload: [UInt8]) throws(ProofFrameError) -> ProofFrame {
        guard payload.count == header.payloadLength else {
            throw .payloadLength(expected: header.payloadLength, actual: payload.count)
        }
        return ProofFrame(kind: try kind(of: header), payload: payload, header: header)
    }

    func encoded() -> [UInt8] {
        header.encoded() + payload
    }

    /// A header declaring one byte more than the 1 MiB budget, for the oversize-refusal fault only. No
    /// `NearbyFrameHeader` can say this, so the bytes are written by hand in its documented layout.
    static func oversizeHeaderBytes(kind: ProofFrameKind) -> [UInt8] {
        let total = UInt32(TransferBudgets.frameBytes + 1)
        return [
            UInt8(truncatingIfNeeded: total >> 24), UInt8(truncatingIfNeeded: total >> 16),
            UInt8(truncatingIfNeeded: total >> 8), UInt8(truncatingIfNeeded: total), kind.rawValue,
            NearbyFrameHeader.version, 0, 0,
        ]
    }
}
