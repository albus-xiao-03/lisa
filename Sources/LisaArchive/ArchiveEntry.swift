// The typed, length-prefixed entries of an archive's payload (plan §8.6.6). Each entry type's schema is defined
// where it is produced (M5 and later); the codec keeps the bytes exact.

/// The kinds of archive entries.
public enum ArchiveEntryKind: UInt8, Hashable, Sendable, CaseIterable {
    /// Eligible exact signed-operation bytes with known receipts and custody acknowledgements.
    case signedOperation = 1
    /// A blob reachable from an exported entry.
    case blob = 2
    /// Unsigned input, its times and intended kind.
    case draft = 3
    /// A conflict: item, field, candidate versions and any draft resolution.
    case conflict = 4
    /// Original R1 queue-entry bytes with their class and evidence (§8.14.3).
    case quarantinedLegacyBytes = 5
    /// A rollback acknowledgement (§8.14.7).
    case rollbackAcknowledgement = 6
    /// A signed, paged reviewed-set artifact referenced by an exported resolution (§8.3.2).
    case reviewedSetArtifact = 7
}

/// One entry: its kind and exact bytes.
public struct ArchiveEntry: Hashable, Sendable {
    /// The largest entry: a 1 MiB blob or a paged artifact with its proofs fits well within it.
    public static let maximumBytes = 16 * 1_048_576

    public let kind: ArchiveEntryKind
    public let bytes: [UInt8]

    public init(kind: ArchiveEntryKind, bytes: [UInt8]) throws(ArchiveError) {
        guard bytes.count <= Self.maximumBytes else { throw .malformedEntries }
        self.kind = kind
        self.bytes = bytes
    }
}

/// The payload layout: for each entry, one kind byte, a 32-bit big-endian length and the bytes.
enum ArchivePayload {
    static func encode(_ entries: [ArchiveEntry]) -> [UInt8] {
        var out: [UInt8] = []
        for entry in entries {
            out.append(entry.kind.rawValue)
            let length = UInt32(entry.bytes.count)
            out += [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)]
            out += entry.bytes
        }
        return out
    }

    static func decode(_ bytes: [UInt8]) throws(ArchiveError) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var index = 0
        while index < bytes.count {
            guard index + 5 <= bytes.count, let kind = ArchiveEntryKind(rawValue: bytes[index]) else {
                throw .malformedEntries
            }
            let length =
                Int(bytes[index + 1]) << 24 | Int(bytes[index + 2]) << 16 | Int(bytes[index + 3]) << 8
                | Int(bytes[index + 4])
            index += 5
            guard length <= ArchiveEntry.maximumBytes, index + length <= bytes.count else { throw .malformedEntries }
            entries.append(try ArchiveEntry(kind: kind, bytes: Array(bytes[index..<(index + length)])))
            index += length
        }
        return entries
    }
}
