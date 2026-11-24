// Who created an operation: a device incarnation, or Core's legacy translation (plan §8.1.1, §8.2.1, §8.12.2).

/// The link from an incarnation's first operation to the previous incarnation and its last sequence number, so a
/// restored device copy shows as a fork instead of repeating an identity (plan §8.1.1).
public struct IncarnationLink: Hashable, Sendable {
    public let incarnationID: Identifier128
    public let lastSequence: Int64

    public init(incarnationID: Identifier128, lastSequence: Int64) throws(OperationEnvelopeError) {
        guard lastSequence >= 1 else { throw .invalidField("previous.lastSequence") }
        self.incarnationID = incarnationID
        self.lastSequence = lastSequence
    }
}

/// The origin of an operation.
public enum OperationOrigin: Hashable, Sendable {
    /// A device incarnation: `(device, incarnation, sequence)` is unique, sequences start at 1, and only the
    /// first operation may name the previous incarnation.
    case device(deviceID: Identifier128, incarnationID: Identifier128, sequence: Int64, previous: IncarnationLink?)
    /// Core's translation of an R1 request into its children (plan §8.12.2).
    case coreLegacyTranslation

    /// The `(device, incarnation, sequence)` triple of a device origin.
    public var deviceTriple: (device: Identifier128, incarnation: Identifier128, sequence: Int64)? {
        guard case .device(let device, let incarnation, let sequence, _) = self else { return nil }
        return (device, incarnation, sequence)
    }

    var canonical: CanonicalValue {
        get throws(CanonicalError) {
            switch self {
            case .coreLegacyTranslation:
                return .object(try CanonicalObject([("kind", .string("coreLegacyTranslation"))]))
            case .device(let device, let incarnation, let sequence, let previous):
                var pairs: [(String, CanonicalValue)] = [
                    ("kind", .string("device")), ("deviceID", .string(device.hex)),
                    ("incarnationID", .string(incarnation.hex)), ("sequence", .integer(sequence)),
                ]
                if let previous {
                    pairs.append(
                        (
                            "previous",
                            .object(
                                try CanonicalObject([
                                    ("incarnationID", .string(previous.incarnationID.hex)),
                                    ("lastSequence", .integer(previous.lastSequence)),
                                ]))
                        ))
                }
                return .object(try CanonicalObject(pairs))
            }
        }
    }

    init(canonical object: CanonicalObject) throws(OperationEnvelopeError) {
        var reader = CanonicalFieldReader(object: object)
        do {
            switch try reader.string("kind") {
            case "coreLegacyTranslation":
                try reader.finish()
                self = .coreLegacyTranslation
            case "device":
                let device = try EnvelopeFields.identifier(reader.string("deviceID"), "origin.deviceID")
                let incarnation = try EnvelopeFields.identifier(reader.string("incarnationID"), "origin.incarnationID")
                let sequence = try reader.integer("sequence")
                guard sequence >= 1 else { throw OperationEnvelopeError.invalidField("origin.sequence") }
                var previous: IncarnationLink?
                if let link = try reader.optionalObject("previous") {
                    var linkReader = CanonicalFieldReader(object: link)
                    previous = try IncarnationLink(
                        incarnationID: EnvelopeFields.identifier(
                            linkReader.string("incarnationID"), "origin.previous.incarnationID"),
                        lastSequence: linkReader.integer("lastSequence"))
                    try linkReader.finish()
                }
                guard previous == nil || sequence == 1 else { throw OperationEnvelopeError.incarnationLink }
                try reader.finish()
                self = .device(deviceID: device, incarnationID: incarnation, sequence: sequence, previous: previous)
            default:
                throw OperationEnvelopeError.invalidField("origin.kind")
            }
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("origin")
        }
    }
}
