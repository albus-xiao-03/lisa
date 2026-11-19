// Sets of IMAP UIDs kept as sorted, merged ranges: the compact form used in commands, and the parsing of a server's
// sequence-set result (ESEARCH ALL) without ever expanding a range.

/// An inclusive range of UIDs; `lower` ≤ `upper`.
struct IMAPUIDRange: Hashable, Sendable {
    let lower: UInt32
    let upper: UInt32

    /// The range between two UIDs in either order, as IMAP ranges are (RFC 9051 §9, seq-range).
    init(_ first: UInt32, _ second: UInt32) {
        lower = min(first, second)
        upper = max(first, second)
    }

    var count: UInt64 { UInt64(upper) - UInt64(lower) + 1 }
}

/// A set of non-zero UIDs as sorted, disjoint, non-adjacent ranges.
struct IMAPUIDSet: Hashable, Sendable {
    private(set) var ranges: [IMAPUIDRange]

    init() { ranges = [] }

    /// The set of `uids`, in any order and with repetitions.
    init(_ uids: [UInt32]) {
        self.init(ranges: uids.map { IMAPUIDRange($0, $0) })
    }

    /// The union of `ranges`.
    init(ranges: [IMAPUIDRange]) {
        var merged: [IMAPUIDRange] = []
        for range in ranges.sorted(by: { $0.lower < $1.lower }) {
            if let last = merged.last, UInt64(range.lower) <= UInt64(last.upper) + 1 {
                merged[merged.count - 1] = IMAPUIDRange(last.lower, max(last.upper, range.upper))
            } else {
                merged.append(range)
            }
        }
        self.ranges = merged
    }

    var isEmpty: Bool { ranges.isEmpty }

    var count: UInt64 { ranges.reduce(0) { $0 + $1.count } }

    func contains(_ uid: UInt32) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = ranges[middle]
            if uid < range.lower {
                high = middle - 1
            } else if uid > range.upper {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    func union(_ other: IMAPUIDSet) -> IMAPUIDSet { IMAPUIDSet(ranges: ranges + other.ranges) }

    /// The smallest `limit` UIDs greater than `floor`, in ascending order.
    func smallest(_ limit: Int, above floor: UInt32) -> [UInt32] {
        var result: [UInt32] = []
        guard limit > 0 else { return result }
        for range in ranges where range.upper > floor {
            var uid = max(range.lower, floor + 1)
            while result.count < limit {
                result.append(uid)
                if uid == range.upper { break }
                uid += 1
            }
            if result.count == limit { break }
        }
        return result
    }

    /// The set as a command argument, such as `1:3,7,9:12` (RFC 9051 §9, sequence-set without `*`).
    var commandText: String {
        ranges.map { $0.lower == $0.upper ? "\($0.lower)" : "\($0.lower):\($0.upper)" }.joined(separator: ",")
    }

    /// Parses a server's UID result, such as ESEARCH `ALL 1:5,9` (RFC 9051 §6.4.4). A result names existing
    /// messages, so `*` is refused, as are zero, numbers beyond 32 bits and more than `maxRanges` elements.
    static func parse(_ bytes: [UInt8], maxRanges: Int) throws(IMAPProtocolError) -> IMAPUIDSet {
        var ranges: [IMAPUIDRange] = []
        var index = 0
        func number() throws(IMAPProtocolError) -> UInt32 {
            if index < bytes.count, bytes[index] == 0x2A {
                throw .malformedResponse("a UID result contained *, which names no message")
            }
            var value: UInt64 = 0
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                value = value * 10 + UInt64(bytes[index] - 0x30)
                guard value <= UInt64(UInt32.max) else { throw .malformedResponse("a UID exceeds 32 bits") }
                index += 1
            }
            guard index > start, value > 0 else { throw .malformedResponse("a UID result contained an invalid UID") }
            return UInt32(value)
        }
        while true {
            let first = try number()
            var second = first
            if index < bytes.count, bytes[index] == 0x3A {
                index += 1
                second = try number()
            }
            ranges.append(IMAPUIDRange(first, second))
            guard ranges.count <= maxRanges else { throw .malformedResponse("a UID result had too many ranges") }
            guard index < bytes.count else { break }
            guard bytes[index] == 0x2C else { throw .malformedResponse("a UID result was malformed") }
            index += 1
        }
        return IMAPUIDSet(ranges: ranges)
    }
}
