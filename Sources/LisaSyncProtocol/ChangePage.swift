// A signed change page (plan §8.4.2): at most 512 KiB, Core-signed over `{dataset, epoch, partitions, fromPosition,
// toPosition, entries ascending by position}`. For every partition it lists, it proves that its entries are all the
// entries in `(from, to]` touching that partition; a listed partition with no entries is proved unchanged over the
// interval. Every page is self-contained. Partitions are named explicitly here; windowed collections' bucket ranges
// join with their schemas.

/// One change page, before or after its signature is checked.
public struct ChangePage: Hashable, Sendable {
    /// The most bytes a page's canonical body may take.
    public static let maximumBytes = 512 << 10
    /// The most partitions one page may list.
    public static let maximumPartitions = 256

    public let datasetID: Identifier128
    public let epochID: Identifier128
    /// Strictly ascending (Unicode scalar order), at least one.
    public let partitions: [String]
    public let fromPosition: Int64
    public let toPosition: Int64
    /// Strictly ascending by position, every one in `(from, to]` and touching a listed partition.
    public let entries: [ChangeEntry]

    public init(
        datasetID: Identifier128, epochID: Identifier128, partitions: [String], fromPosition: Int64, toPosition: Int64,
        entries: [ChangeEntry]
    ) throws(OperationEnvelopeError) {
        guard !partitions.isEmpty, partitions.count <= Self.maximumPartitions,
            zip(partitions, partitions.dropFirst()).allSatisfy({
                $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars)
            }), partitions.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 })
        else { throw .invalidField("page.partitions") }
        guard fromPosition >= 0, toPosition > fromPosition else { throw .invalidField("page.interval") }
        let listed = Set(partitions)
        guard zip(entries, entries.dropFirst()).allSatisfy({ $0.position < $1.position }),
            entries.allSatisfy({
                $0.position > fromPosition && $0.position <= toPosition && !listed.isDisjoint(with: $0.partitions)
            })
        else { throw .invalidField("page.entries") }
        self.datasetID = datasetID
        self.epochID = epochID
        self.partitions = partitions
        self.fromPosition = fromPosition
        self.toPosition = toPosition
        self.entries = entries
    }

    /// The canonical body Core signs; refused over 512 KiB.
    public func canonicalBody() throws(OperationEnvelopeError) -> [UInt8] {
        do {
            var entryValues: [CanonicalValue] = []
            for entry in entries { entryValues.append(try entry.canonicalValue) }
            let object = try CanonicalObject([
                ("datasetID", .string(datasetID.hex)), ("epochID", .string(epochID.hex)),
                ("partitions", .array(partitions.map { .string($0) })), ("fromPosition", .integer(fromPosition)),
                ("toPosition", .integer(toPosition)), ("entries", .array(entryValues)),
            ])
            return try CanonicalEncoder.encode(.object(object), limits: CanonicalLimits(maxBytes: Self.maximumBytes))
        } catch {
            throw .encoding(error)
        }
    }

    /// Decodes a page body strictly: canonical JSON within 512 KiB, every field by its rules, no unknown fields.
    public static func decode(body: [UInt8]) throws(OperationEnvelopeError) -> ChangePage {
        do {
            var reader = try CanonicalFieldReader(
                CanonicalDecoder.decode(body, limits: CanonicalLimits(maxBytes: Self.maximumBytes)))
            let partitions = try reader.array("partitions").map { value in
                guard case .string(let name) = value else {
                    throw OperationEnvelopeError.invalidField("page.partitions")
                }
                return name
            }
            let entries = try reader.array("entries").map { try ChangeEntry(canonicalValue: $0) }
            let page = try ChangePage(
                datasetID: EnvelopeFields.identifier(reader.string("datasetID"), "page.datasetID"),
                epochID: EnvelopeFields.identifier(reader.string("epochID"), "page.epochID"), partitions: partitions,
                fromPosition: reader.integer("fromPosition"), toPosition: reader.integer("toPosition"), entries: entries
            )
            try reader.finish()
            return page
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("page")
        }
    }
}
