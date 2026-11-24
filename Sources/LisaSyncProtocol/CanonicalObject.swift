// A canonical JSON object: members sorted by Unicode scalar value, each key unique (plan §8.16.1).

/// A JSON object in canonical form.
///
/// Members are kept sorted by the Unicode scalar values of their keys. Construction refuses a key that repeats
/// another exactly or that is canonically equivalent to another (Swift would treat such keys as one), so every
/// consumer sees the same members the signer saw.
public struct CanonicalObject: Sendable {
    /// One key and its value.
    public struct Member: Sendable {
        public let key: String
        public let value: CanonicalValue
    }

    /// The members in canonical order.
    public let members: [Member]

    /// The empty object.
    public static let empty = CanonicalObject(sortedUniqueMembers: [])

    /// Builds an object from key–value pairs in any order.
    /// - Throws: `CanonicalError.duplicateKey` for a repeated or canonically equivalent key.
    public init(_ pairs: [(String, CanonicalValue)]) throws(CanonicalError) {
        var seen = Set<String>()
        for (key, _) in pairs where !seen.insert(key).inserted {
            throw .duplicateKey(key)
        }
        let sorted = pairs.sorted { UnicodeScalarOrder.precedes($0.0, $1.0) }
        members = sorted.map { Member(key: $0.0, value: $0.1) }
    }

    /// Builds an object from members already sorted and unique, as the decoder produces them.
    init(sortedUniqueMembers: [Member]) {
        members = sortedUniqueMembers
    }

    /// The number of members.
    public var count: Int { members.count }

    /// The keys in canonical order.
    public var keys: [String] { members.map(\.key) }

    /// The value for a key with exactly these Unicode scalars, or `nil`.
    public subscript(key: String) -> CanonicalValue? {
        var low = 0
        var high = members.count
        while low < high {
            let middle = (low + high) / 2
            let candidate = members[middle].key
            if UnicodeScalarOrder.identical(candidate, key) { return members[middle].value }
            if UnicodeScalarOrder.precedes(candidate, key) { low = middle + 1 } else { high = middle }
        }
        return nil
    }
}

extension CanonicalObject.Member: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key.utf8.elementsEqual(rhs.key.utf8) && lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        for byte in key.utf8 { hasher.combine(byte) }
        hasher.combine(value)
    }
}

extension CanonicalObject: Hashable {}
