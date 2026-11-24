// The payloads of the task family and of the pieces every owner item has (plan §8.2.3, §8.3.2): canonical forms and
// their strict decoding. What an operation replaces or removes is never in its payload but in its observed set.
//
//   task.create            {"confirmation","deadline","estimate","priority","splittable","title"}  (all six present)
//   task.edit              {"field": <task field>, "value": <its value>}
//   task.complete          {}
//   task.cancel            {}
//   task.reopen            {"reopens": [terminal-action operation IDs, strictly ascending, 1–32]}
//   note.add               {"text": <the note piece>}
//   note.replaceObserved   {"text": <the replacement>}   (replaces the observed note pieces)
//   tags.change            {"change": "add" | "remove", "tag": <1–64 characters>}   (a removal covers what it observed)
//   item.delete            {}
//   conflict.resolve       {"field": <task field>, "value"?: <its value>}   (the value on a single resolution and on a
//                          group's final page only; the candidates it resolves are its observed set, §8.3.2)
//
// A note's text is limited by the type's value budget (plan §8.3.3), measured on its encoded bytes after canonical
// escaping, quotes excluded, before anything larger is built: `maximumTextBytes(operationType:)`.

/// A decoded payload of an item operation.
public enum ItemOperationPayload: Hashable, Sendable {
    case taskCreate(TaskCreation)
    case taskEdit(TaskFieldValue)
    case taskComplete
    case taskCancel
    case taskReopen(reopens: [Identifier128])
    case noteAdd(text: String)
    case noteReplaceObserved(text: String)
    case tagChange(tag: String, added: Bool)
    case itemDelete
    /// A resolution of one field's conflict, or one page of a paged resolution group (no value before its last page).
    case conflictResolve(field: TaskField, value: TaskFieldValue?)

    public static let maximumReopens = 32
    public static let maximumTagCharacters = 64

    /// The operation types these payloads belong to.
    public static let operationTypes: Set<String> = [
        "task.create", "task.edit", "task.complete", "task.cancel", "task.reopen", "note.add", "note.replaceObserved",
        "tags.change", "item.delete", "conflict.resolve",
    ]

    public var operationType: String {
        switch self {
        case .taskCreate: "task.create"
        case .taskEdit: "task.edit"
        case .taskComplete: "task.complete"
        case .taskCancel: "task.cancel"
        case .taskReopen: "task.reopen"
        case .noteAdd: "note.add"
        case .noteReplaceObserved: "note.replaceObserved"
        case .tagChange: "tags.change"
        case .itemDelete: "item.delete"
        case .conflictResolve: "conflict.resolve"
        }
    }

    /// Checks the rules of the payload's own fields.
    public init(validating payload: ItemOperationPayload) throws(OperationEnvelopeError) {
        switch payload {
        case .taskCreate, .taskComplete, .taskCancel, .itemDelete:
            break
        case .taskEdit(let value):
            _ = try TaskFieldValue(validating: value)
        case .taskReopen(let reopens):
            guard !reopens.isEmpty, reopens.count <= Self.maximumReopens, EnvelopeFields.isStrictlyAscending(reopens)
            else { throw .invalidField("payload.reopens") }
        case .noteAdd(let text), .noteReplaceObserved(let text):
            guard !text.isEmpty else { throw .invalidField("payload.text") }
            let limit = Self.textLimits[payload.operationType] ?? 0
            let bytes = CanonicalEncoder.encodedLength(ofString: text) - 2
            guard bytes <= limit else { throw .encoding(.tooLarge(bytes: bytes, limit: limit)) }
        case .tagChange(let tag, _):
            guard !tag.isEmpty, tag.count <= Self.maximumTagCharacters else { throw .invalidField("payload.tag") }
        case .conflictResolve(let field, let value):
            if let value {
                guard value.field == field else { throw .invalidField("payload.value") }
                _ = try TaskFieldValue(validating: value)
            }
        }
        self = payload
    }

    /// The most encoded bytes a note's text may take, after canonical escaping and quotes excluded: the type's value
    /// budget (`OperationValueBudget`), adjusted by this schema's own keys — `{"text":…}` is one byte shorter than the
    /// budget's reference payload `{"value":…}`.
    public static func maximumTextBytes(operationType: String) throws(OperationEnvelopeError) -> Int {
        let budget = try OperationValueBudget.maximumValueBytes(type: operationType)
        do {
            let reference = try CanonicalEncoder.encodedLength(
                of: .object(try CanonicalObject([("value", .string(""))])))
            let own = try CanonicalEncoder.encodedLength(of: .object(try CanonicalObject([("text", .string(""))])))
            return budget + reference - own
        } catch {
            throw .encoding(error)
        }
    }

    private static let textLimits: [String: Int] = {
        var limits: [String: Int] = [:]
        for type in ["note.add", "note.replaceObserved"] {
            limits[type] = (try? maximumTextBytes(operationType: type)) ?? 0
        }
        return limits
    }()

    public var canonicalValue: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .taskCreate(let creation):
                var pairs: [(String, CanonicalValue)] = []
                for value in creation.fieldValues { pairs.append((value.field.rawValue, try value.canonicalValue)) }
                return .object(try CanonicalObject(pairs))
            case .taskEdit(let value):
                return .object(
                    try CanonicalObject([("field", .string(value.field.rawValue)), ("value", try value.canonicalValue)])
                )
            case .taskComplete, .taskCancel, .itemDelete:
                return .object(.empty)
            case .taskReopen(let reopens):
                return .object(try CanonicalObject([("reopens", .array(reopens.map { .string($0.hex) }))]))
            case .noteAdd(let text), .noteReplaceObserved(let text):
                return .object(try CanonicalObject([("text", .string(text))]))
            case .tagChange(let tag, let added):
                return .object(
                    try CanonicalObject([("change", .string(added ? "add" : "remove")), ("tag", .string(tag))]))
            case .conflictResolve(let field, let value):
                var pairs: [(String, CanonicalValue)] = [("field", .string(field.rawValue))]
                if let value { pairs.append(("value", try value.canonicalValue)) }
                return .object(try CanonicalObject(pairs))
            }
        }
    }

    /// Decodes the payload of `operationType` strictly: its fields only, each by its rules.
    public init(operationType: String, payload: CanonicalValue) throws(OperationEnvelopeError) {
        do {
            var reader = try CanonicalFieldReader(payload)
            let decoded: ItemOperationPayload
            switch operationType {
            case "task.create":
                func field(_ name: TaskField) throws -> TaskFieldValue {
                    try TaskFieldValue(field: name, canonicalValue: reader.value(name.rawValue))
                }
                guard case .title(let title) = try field(.title), case .priority(let priority) = try field(.priority),
                    case .deadline(let deadline) = try field(.deadline),
                    case .estimate(let estimate) = try field(.estimate),
                    case .splittable(let splittable) = try field(.splittable),
                    case .confirmation(let confirmation) = try field(.confirmation)
                else { throw OperationEnvelopeError.invalidField("payload") }
                decoded = .taskCreate(
                    try TaskCreation(
                        title: title, priority: priority, deadline: deadline, estimate: estimate,
                        splittable: splittable,
                        confirmation: confirmation))
            case "task.edit":
                guard let field = TaskField(rawValue: try reader.string("field")) else {
                    throw OperationEnvelopeError.invalidField("payload.field")
                }
                decoded = .taskEdit(try TaskFieldValue(field: field, canonicalValue: reader.value("value")))
            case "task.complete": decoded = .taskComplete
            case "task.cancel": decoded = .taskCancel
            case "item.delete": decoded = .itemDelete
            case "task.reopen":
                decoded = .taskReopen(
                    reopens: try reader.array("reopens").map { value in
                        guard case .string(let hex) = value else {
                            throw OperationEnvelopeError.invalidField("payload.reopens")
                        }
                        return try EnvelopeFields.identifier(hex, "payload.reopens")
                    })
            case "note.add": decoded = .noteAdd(text: try reader.string("text"))
            case "note.replaceObserved": decoded = .noteReplaceObserved(text: try reader.string("text"))
            case "tags.change":
                let change = try reader.string("change")
                guard change == "add" || change == "remove" else {
                    throw OperationEnvelopeError.invalidField("payload.change")
                }
                decoded = .tagChange(tag: try reader.string("tag"), added: change == "add")
            case "conflict.resolve":
                guard let field = TaskField(rawValue: try reader.string("field")) else {
                    throw OperationEnvelopeError.invalidField("payload.field")
                }
                let value = try reader.optionalValue("value").map {
                    try TaskFieldValue(field: field, canonicalValue: $0)
                }
                decoded = .conflictResolve(field: field, value: value)
            default:
                throw OperationEnvelopeError.invalidField("type")
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
