// The preference operations (plan §8.2.3; docs/DECISIONS.md D-73): set, delete or confirm one key, with the key in
// the payload. A preference is a register per key, so its entity ID is derived from the key (`PreferenceEntity`,
// LisaTrust). Whether a key and its value are supported is R1's rule, checked at Core. A number travels as the shortest
// decimal text that reads back as the same finite value, because canonical JSON carries integers only.
//
//   preference.set       {"key": <key>, "value": <value>}
//   preference.delete    {"key": <key>}
//   preference.confirm   {"key": <key>}
//
//   <value>  {"kind":"text","text":<string>} | {"kind":"number","number":<decimal text>} |
//            {"kind":"flag","flag":<bool>} | {"kind":"list","list":[<string>, …]}
//
// A key is 1–256 UTF-8 bytes without control characters, as R1 accepts any key text and refuses unsupported ones
// itself. A list holds at most 256 strings. The whole payload fits the type's value budget (plan §8.3.3).

/// A preference value on the wire.
public enum PreferenceWireValue: Hashable, Sendable {
    case text(String)
    /// The shortest decimal text that reads back as the same finite number.
    case number(String)
    case flag(Bool)
    case list([String])

    /// `value` in its wire form; `nil` for a value that isn't finite.
    public static func number(_ value: Double) -> PreferenceWireValue? {
        value.isFinite ? .number(value.description) : nil
    }

    /// The number's value, for `.number`.
    public var number: Double? {
        if case .number(let text) = self { Double(text) } else { nil }
    }

    var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .text(let text):
                .object(try CanonicalObject([("kind", .string("text")), ("text", .string(text))]))
            case .number(let text):
                .object(try CanonicalObject([("kind", .string("number")), ("number", .string(text))]))
            case .flag(let flag):
                .object(try CanonicalObject([("kind", .string("flag")), ("flag", .bool(flag))]))
            case .list(let items):
                .object(try CanonicalObject([("kind", .string("list")), ("list", .array(items.map { .string($0) }))]))
            }
        }
    }

    init(canonicalValue value: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            guard case .object(let object) = value else { throw OperationEnvelopeError.invalidField("payload.value") }
            var reader = CanonicalFieldReader(object: object)
            switch try reader.string("kind") {
            case "text": self = .text(try reader.string("text"))
            case "number": self = .number(try reader.string("number"))
            case "flag": self = .flag(try reader.bool("flag"))
            case "list":
                self = .list(
                    try reader.array("list").map { item in
                        guard case .string(let text) = item else {
                            throw OperationEnvelopeError.invalidField("payload.value.list")
                        }
                        return text
                    })
            default: throw OperationEnvelopeError.invalidField("payload.value.kind")
            }
            try reader.finish()
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("payload.value")
        }
    }
}

/// A decoded payload of a preference operation.
public enum PreferenceOperationPayload: Hashable, Sendable {
    case set(key: String, value: PreferenceWireValue)
    case delete(key: String)
    case confirm(key: String)

    public static let maximumKeyBytes = 256
    public static let maximumListItems = 256

    /// The operation types these payloads belong to.
    public static let operationTypes: Set<String> = ["preference.set", "preference.delete", "preference.confirm"]

    public var operationType: String {
        switch self {
        case .set: "preference.set"
        case .delete: "preference.delete"
        case .confirm: "preference.confirm"
        }
    }

    public var key: String {
        switch self {
        case .set(let key, _), .delete(let key), .confirm(let key): key
        }
    }

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .set(let key, let value):
                .object(try CanonicalObject([("key", .string(key)), ("value", try value.canonicalValue)]))
            case .delete(let key), .confirm(let key):
                .object(try CanonicalObject([("key", .string(key))]))
            }
        }
    }

    /// Checks the rules of the payload's own fields.
    public init(validating payload: PreferenceOperationPayload) throws(OperationEnvelopeError) {
        let key = payload.key
        guard !key.isEmpty, key.utf8.count <= Self.maximumKeyBytes,
            !key.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw .invalidField("payload.key") }
        if case .set(_, let value) = payload {
            switch value {
            case .number(let text):
                guard let number = Double(text), number.isFinite, number.description == text else {
                    throw .invalidField("payload.value.number")
                }
            case .list(let items):
                guard items.count <= Self.maximumListItems else { throw .invalidField("payload.value.list") }
            case .text, .flag:
                break
            }
        }
        let limit = try OperationValueBudget.maximumValueBytes(type: payload.operationType)
        let bytes: Int
        do {
            bytes = try CanonicalEncoder.encodedLength(of: try payload.canonicalValue)
        } catch {
            throw .encoding(error)
        }
        guard bytes <= limit else { throw .encoding(.tooLarge(bytes: bytes, limit: limit)) }
        self = payload
    }

    /// Decodes the payload of `operationType` strictly: its fields only, each by its rules.
    public init(operationType: String, payload: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(payload)
            let key = try reader.string("key")
            let decoded: PreferenceOperationPayload
            switch operationType {
            case "preference.set":
                decoded = .set(key: key, value: try PreferenceWireValue(canonicalValue: reader.value("value")))
            case "preference.delete": decoded = .delete(key: key)
            case "preference.confirm": decoded = .confirm(key: key)
            default: throw OperationEnvelopeError.invalidField("type")
            }
            try reader.finish()
            try self.init(validating: decoded)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("payload")
        }
    }
}
