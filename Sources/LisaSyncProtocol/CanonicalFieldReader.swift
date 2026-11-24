// Typed reading of a canonical object's fields that refuses unknown fields (plan §8.2.1: no unknown envelope fields).

/// Reads the fields of one canonical object by name and type. Call `finish()` after the last field: any member that
/// was never read is an unknown field, and the object is refused.
public struct CanonicalFieldReader {
    let object: CanonicalObject
    var read: [String] = []

    /// - Throws: `CanonicalFieldError.notAnObject` unless `value` is an object.
    public init(_ value: CanonicalValue) throws(CanonicalFieldError) {
        guard case .object(let object) = value else { throw .notAnObject }
        self.object = object
    }

    public init(object: CanonicalObject) {
        self.object = object
    }

    mutating func lookup(_ key: String) -> CanonicalValue? {
        read.append(key)
        return object[key]
    }

    /// The value of a required field, of any type.
    public mutating func value(_ key: String) throws(CanonicalFieldError) -> CanonicalValue {
        guard let value = lookup(key) else { throw .missing(key) }
        return value
    }

    /// The value of an optional field; an absent field is `nil` (an explicit JSON null is not absence).
    public mutating func optionalValue(_ key: String) -> CanonicalValue? {
        lookup(key)
    }

    public mutating func string(_ key: String) throws(CanonicalFieldError) -> String {
        guard case .string(let string) = try value(key) else { throw .wrongType(key, expected: "string") }
        return string
    }

    public mutating func optionalString(_ key: String) throws(CanonicalFieldError) -> String? {
        guard let value = lookup(key) else { return nil }
        guard case .string(let string) = value else { throw .wrongType(key, expected: "string") }
        return string
    }

    public mutating func integer(_ key: String) throws(CanonicalFieldError) -> Int64 {
        guard case .integer(let number) = try value(key) else { throw .wrongType(key, expected: "integer") }
        return number
    }

    public mutating func optionalInteger(_ key: String) throws(CanonicalFieldError) -> Int64? {
        guard let value = lookup(key) else { return nil }
        guard case .integer(let number) = value else { throw .wrongType(key, expected: "integer") }
        return number
    }

    public mutating func bool(_ key: String) throws(CanonicalFieldError) -> Bool {
        guard case .bool(let flag) = try value(key) else { throw .wrongType(key, expected: "boolean") }
        return flag
    }

    public mutating func object(_ key: String) throws(CanonicalFieldError) -> CanonicalObject {
        guard case .object(let object) = try value(key) else { throw .wrongType(key, expected: "object") }
        return object
    }

    public mutating func optionalObject(_ key: String) throws(CanonicalFieldError) -> CanonicalObject? {
        guard let value = lookup(key) else { return nil }
        guard case .object(let object) = value else { throw .wrongType(key, expected: "object") }
        return object
    }

    public mutating func array(_ key: String) throws(CanonicalFieldError) -> [CanonicalValue] {
        guard case .array(let elements) = try value(key) else { throw .wrongType(key, expected: "array") }
        return elements
    }

    /// Bytes carried as an unpadded base64url string.
    public mutating func bytes(_ key: String) throws(CanonicalFieldError) -> [UInt8] {
        let text = try string(key)
        do {
            return try StrictBase64URL.decode(text)
        } catch {
            throw .invalidEncoding(key)
        }
    }

    /// Refuses the object if it has a member that was never read.
    public func finish() throws(CanonicalFieldError) {
        let unknown = object.keys.filter { key in !read.contains { UnicodeScalarOrder.identical($0, key) } }
        guard unknown.isEmpty else { throw .unknownFields(unknown) }
    }
}

/// Why a canonical object did not match the expected shape.
public enum CanonicalFieldError: Error, Hashable, Sendable {
    case notAnObject
    case missing(String)
    case wrongType(String, expected: String)
    case invalidEncoding(String)
    case unknownFields([String])
}
