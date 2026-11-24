// The archive header (plan §8.6.6): what the archive is, who can open it and who signed it.

import LisaSyncProtocol

/// The header of a `lisa-archive` v1 file, carried as canonical JSON. Its SHA-256 is the payload cipher's
/// authenticated data and half of what the exporting device signs.
public struct ArchiveHeader: Hashable, Sendable {
    public static let format = "lisa-archive"
    public static let formatVersion: Int64 = 1

    public let archiveID: Identifier128
    public let datasetID: Identifier128
    public let originDeviceID: Identifier128
    /// The incarnations whose work the archive covers, strictly ascending.
    public let incarnations: [Identifier128]
    /// Unix milliseconds.
    public let createdAt: Int64
    public let rosterVersion: Int64
    /// The head known at export.
    public let head: Digest256
    /// At least one, strictly ascending by key ID.
    public let recipients: [ArchiveRecipient]
    /// The exporting device's signing key ID, or `nil` for an unsigned archive (its key was unavailable).
    public let signerKeyID: Digest256?
    public let payloadNonce: [UInt8]
    public let payloadLength: Int64

    public init(
        archiveID: Identifier128, datasetID: Identifier128, originDeviceID: Identifier128,
        incarnations: [Identifier128], createdAt: Int64, rosterVersion: Int64, head: Digest256,
        recipients: [ArchiveRecipient], signerKeyID: Digest256?, payloadNonce: [UInt8], payloadLength: Int64
    ) throws(ArchiveError) {
        guard zip(incarnations, incarnations.dropFirst()).allSatisfy({ $0.bytes.lexicographicallyPrecedes($1.bytes) })
        else { throw .malformedHeader("incarnations") }
        guard !recipients.isEmpty,
            zip(recipients, recipients.dropFirst()).allSatisfy({
                $0.keyID.bytes.lexicographicallyPrecedes($1.keyID.bytes)
            })
        else { throw .malformedHeader("recipients") }
        guard payloadNonce.count == 12 else { throw .malformedHeader("payloadNonce") }
        guard createdAt >= 0, rosterVersion >= 0, payloadLength >= 16 else { throw .malformedHeader("integers") }
        self.archiveID = archiveID
        self.datasetID = datasetID
        self.originDeviceID = originDeviceID
        self.incarnations = incarnations
        self.createdAt = createdAt
        self.rosterVersion = rosterVersion
        self.head = head
        self.recipients = recipients
        self.signerKeyID = signerKeyID
        self.payloadNonce = payloadNonce
        self.payloadLength = payloadLength
    }

    /// The canonical header bytes.
    public func canonicalBody() throws(ArchiveError) -> [UInt8] {
        do {
            var pairs: [(String, CanonicalValue)] = [
                ("format", .string(Self.format)), ("formatVersion", .integer(Self.formatVersion)),
                ("archiveID", .string(archiveID.hex)), ("datasetID", .string(datasetID.hex)),
                ("originDeviceID", .string(originDeviceID.hex)),
                ("incarnations", .array(incarnations.map { .string($0.hex) })), ("createdAt", .integer(createdAt)),
                ("rosterVersion", .integer(rosterVersion)), ("head", .string(head.hex)),
                ("payloadNonce", .string(StrictBase64URL.encode(payloadNonce))),
                ("payloadLength", .integer(payloadLength)),
            ]
            pairs.append(
                (
                    "recipients",
                    .array(
                        try recipients.map { recipient in
                            .object(
                                try CanonicalObject([
                                    ("kind", .string(recipient.kind.rawValue)), ("keyID", .string(recipient.keyID.hex)),
                                    ("encapsulatedKey", .string(StrictBase64URL.encode(recipient.encapsulatedKey))),
                                    ("sealedKey", .string(StrictBase64URL.encode(recipient.sealedKey))),
                                ]))
                        })
                ))
            if let signerKeyID { pairs.append(("signerKeyID", .string(signerKeyID.hex))) }
            return try CanonicalEncoder.encode(
                .object(try CanonicalObject(pairs)),
                limits: CanonicalLimits(maxBytes: ArchiveContainer.maximumHeaderBytes))
        } catch {
            throw .malformedHeader("encoding")
        }
    }

    /// Decodes a header strictly: canonical JSON, the format and version, every field rule, no unknown fields.
    public static func decode(_ body: [UInt8]) throws(ArchiveError) -> ArchiveHeader {
        guard
            let value = try? CanonicalDecoder.decode(
                body, limits: CanonicalLimits(maxBytes: ArchiveContainer.maximumHeaderBytes)),
            var reader = try? CanonicalFieldReader(value)
        else { throw .malformedHeader("encoding") }
        do {
            guard try reader.string("format") == format, try reader.integer("formatVersion") == formatVersion else {
                throw ArchiveError.malformedHeader("format")
            }
            let recipients = try reader.array("recipients").map { (item) throws -> ArchiveRecipient in
                var r = try CanonicalFieldReader(item)
                guard let kind = ArchiveRecipientKind(rawValue: try r.string("kind")) else {
                    throw ArchiveError.malformedHeader("recipient kind")
                }
                let recipient = ArchiveRecipient(
                    kind: kind, keyID: try Digest256(hex: r.string("keyID")),
                    encapsulatedKey: try r.bytes("encapsulatedKey"), sealedKey: try r.bytes("sealedKey"))
                try r.finish()
                return recipient
            }
            let incarnations = try reader.array("incarnations").map { (item) throws -> Identifier128 in
                guard case .string(let hex) = item else { throw ArchiveError.malformedHeader("incarnations") }
                return try Identifier128(hex: hex)
            }
            let header = try ArchiveHeader(
                archiveID: Identifier128(hex: reader.string("archiveID")),
                datasetID: Identifier128(hex: reader.string("datasetID")),
                originDeviceID: Identifier128(hex: reader.string("originDeviceID")), incarnations: incarnations,
                createdAt: reader.integer("createdAt"), rosterVersion: reader.integer("rosterVersion"),
                head: Digest256(hex: reader.string("head")), recipients: recipients,
                signerKeyID: reader.optionalString("signerKeyID").map { try Digest256(hex: $0) },
                payloadNonce: reader.bytes("payloadNonce"), payloadLength: reader.integer("payloadLength"))
            try reader.finish()
            return header
        } catch let error as ArchiveError {
            throw error
        } catch {
            throw .malformedHeader("fields")
        }
    }
}
