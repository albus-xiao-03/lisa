// The nearby frame header (plan §8.16.2: an 8-byte header and the payload, at most 1 MiB in total, checked from the
// header before allocation; §8.7 exchanges in frames).

/// The 8-byte header in front of every nearby frame:
///
///     bytes 0–3   total length, header included, unsigned big-endian (8 ... 1_048_576)
///     byte  4     kind (the session layer's registry)
///     byte  5     header version, 1
///     bytes 6–7   reserved, zero
///
/// A receiver reads exactly 8 bytes, parses them, and only then reads `payloadLength` more: the budget is enforced
/// from the header, so no buffer larger than 1 MiB is ever allocated for a frame.
public struct NearbyFrameHeader: Hashable, Sendable {
    public static let length = TransferBudgets.frameHeaderBytes
    public static let version: UInt8 = 1
    /// The largest payload a frame can carry: the frame budget minus the header.
    public static let maximumPayloadBytes = TransferBudgets.frameBytes - TransferBudgets.frameHeaderBytes

    public let kind: UInt8
    /// The whole frame's length, header included.
    public let totalLength: Int

    /// The payload's length.
    public var payloadLength: Int { totalLength - Self.length }

    /// The header for a payload of `payloadLength` bytes; refused if the frame would leave the budget.
    public init(kind: UInt8, payloadLength: Int) throws(NearbyFrameError) {
        let (total, overflow) = payloadLength.addingReportingOverflow(Self.length)
        do {
            try TransferBudgets.checkFrame(totalBytes: overflow ? Int.max : total)
        } catch {
            throw .budget(error)
        }
        self.init(checkedKind: kind, totalLength: total)
    }

    private init(checkedKind kind: UInt8, totalLength: Int) {
        self.kind = kind
        self.totalLength = totalLength
    }

    /// Reads a received header: exactly 8 bytes, a total within the budget, version 1, reserved bytes zero. The kind
    /// is returned as is; the session layer decides whether it knows it.
    public static func parse(_ bytes: some Collection<UInt8>) throws(NearbyFrameError) -> NearbyFrameHeader {
        let header = Array(bytes)
        guard header.count == length else { throw .headerLength(header.count) }
        let total = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
        do {
            try TransferBudgets.checkFrame(totalBytes: total)
        } catch {
            throw .budget(error)
        }
        guard header[5] == version else { throw .unsupportedVersion(header[5]) }
        guard header[6] == 0, header[7] == 0 else { throw .reservedBytesSet }
        return NearbyFrameHeader(checkedKind: header[4], totalLength: total)
    }

    /// The 8 header bytes.
    public func encoded() -> [UInt8] {
        // At most 1 MiB, so it fits in four bytes.
        let total = UInt32(totalLength)
        return [
            UInt8(truncatingIfNeeded: total >> 24), UInt8(truncatingIfNeeded: total >> 16),
            UInt8(truncatingIfNeeded: total >> 8), UInt8(truncatingIfNeeded: total), kind, Self.version, 0, 0,
        ]
    }
}
