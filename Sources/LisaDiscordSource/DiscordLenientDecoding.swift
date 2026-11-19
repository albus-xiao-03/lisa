// Lenient JSON decoding helpers for Discord objects: optional members and bounded arrays that skip malformed elements.

/// A value that decodes from any JSON value and keeps nothing, used to step over an element that did not decode.
struct DiscordSkippedValue: Decodable {
    init(from decoder: any Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// The member's value, or nil when it is absent, null or of another type.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Up to `limit` elements of an array member that decode as `T`; elements that do not are skipped. An absent,
    /// null or non-array member yields no elements.
    func lenientArray<T: Decodable>(_ type: T.Type, forKey key: Key, limit: Int) -> [T] {
        guard contains(key), (try? decodeNil(forKey: key)) == false,
            var elements = try? nestedUnkeyedContainer(forKey: key)
        else { return [] }
        var values: [T] = []
        var visited = 0
        while !elements.isAtEnd, visited < limit {
            visited += 1
            if let value = try? elements.decode(type) {
                values.append(value)
            } else if (try? elements.decode(DiscordSkippedValue.self)) == nil {
                break
            }
        }
        return values
    }

    /// The number of elements of an array member; zero when it is absent, null or not an array.
    func arrayCount(forKey key: Key) -> Int {
        guard contains(key), (try? decodeNil(forKey: key)) == false,
            let elements = try? nestedUnkeyedContainer(forKey: key)
        else { return 0 }
        return elements.count ?? 0
    }

    /// Whether the member is present and not null.
    func isPresent(_ key: Key) -> Bool {
        contains(key) && (try? decodeNil(forKey: key)) == false
    }
}
