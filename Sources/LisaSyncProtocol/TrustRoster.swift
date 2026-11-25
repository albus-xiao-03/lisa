// The roster (plan §8.1.3): Core's signed statement of the dataset's devices, with each device's keys, status and
// capabilities, the revocations with the epoch and position at which they happened, the TLS pins (current and next),
// Core's export key and the anchors-bundle digest. It travels as a paged artifact of type `roster` (§9): page 0 is the
// summary, then the device pages, then the revocation pages, each a canonical JSON object. The signed header binds the
// ordered pages, so a peer can neither drop a revocation page nor reorder pages, and the summary's counts say how many
// pages of each kind there are.

/// One device as the roster lists it.
public struct RosterDevice: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case active
        case revoked
    }

    public enum DeviceClass: String, Hashable, Sendable {
        case iphone
        case ipad
        case mac
    }

    /// The longest device name, in UTF-8 bytes.
    public static let maximumNameBytes = 64
    /// The most capabilities one device lists.
    public static let maximumCapabilities = 32

    public let deviceID: Identifier128
    public let name: String
    public let deviceClass: DeviceClass
    public let status: Status
    /// The operation-signing key: canonical P-256 SubjectPublicKeyInfo DER (§8.1.1).
    public let operationKey: [UInt8]
    /// The device export key (P-256 key agreement): canonical SubjectPublicKeyInfo DER.
    public let exportKey: [UInt8]
    /// When the device enrolled, in Unix milliseconds.
    public let enrolledAt: Int64
    /// Strictly ascending capability tokens.
    public let capabilities: [String]

    public init(
        deviceID: Identifier128, name: String, deviceClass: DeviceClass, status: Status, operationKey: [UInt8],
        exportKey: [UInt8], enrolledAt: Int64, capabilities: [String] = []
    ) throws(OperationEnvelopeError) {
        guard Self.isValidName(name) else { throw .invalidField("roster.device.name") }
        guard (1...256).contains(operationKey.count), (1...256).contains(exportKey.count) else {
            throw .invalidField("roster.device.keys")
        }
        guard capabilities.count <= Self.maximumCapabilities,
            capabilities.allSatisfy({ WireText.isToken($0, length: 1...64) }),
            zip(capabilities, capabilities.dropFirst()).allSatisfy({ $0 < $1 })
        else { throw .invalidField("roster.device.capabilities") }
        self.deviceID = deviceID
        self.name = name
        self.deviceClass = deviceClass
        self.status = status
        self.operationKey = operationKey
        self.exportKey = exportKey
        self.enrolledAt = enrolledAt
        self.capabilities = capabilities
    }

    /// 1 to 64 UTF-8 bytes without control characters.
    public static func isValidName(_ name: String) -> Bool {
        (1...maximumNameBytes).contains(name.utf8.count)
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    func canonicalValue() throws -> CanonicalValue {
        .object(
            try CanonicalObject([
                ("deviceID", .string(deviceID.hex)), ("name", .string(name)),
                ("deviceClass", .string(deviceClass.rawValue)), ("status", .string(status.rawValue)),
                ("operationKey", .string(StrictBase64URL.encode(operationKey))),
                ("exportKey", .string(StrictBase64URL.encode(exportKey))), ("enrolledAt", .integer(enrolledAt)),
                ("capabilities", .array(capabilities.map { .string($0) })),
            ]))
    }

    static func decode(_ value: CanonicalValue) throws -> RosterDevice {
        var reader = try CanonicalFieldReader(value)
        guard let deviceClass = DeviceClass(rawValue: try reader.string("deviceClass")),
            let status = Status(rawValue: try reader.string("status"))
        else { throw OperationEnvelopeError.invalidField("roster.device") }
        let capabilities = try reader.array("capabilities").map { value in
            guard case .string(let text) = value else { throw OperationEnvelopeError.invalidField("roster.device") }
            return text
        }
        let device = try RosterDevice(
            deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "roster.device.deviceID"),
            name: reader.string("name"), deviceClass: deviceClass, status: status,
            operationKey: reader.bytes("operationKey"), exportKey: reader.bytes("exportKey"),
            enrolledAt: reader.integer("enrolledAt"), capabilities: capabilities)
        try reader.finish()
        return device
    }
}

/// A revocation: permanent, whatever later roster, epoch or restore follows (the union rule).
public struct RosterRevocation: Hashable, Sendable {
    public let deviceID: Identifier128
    public let epochID: Identifier128
    /// The commit position at which the revocation happened.
    public let position: Int64
    public let revokedAt: Int64

    public init(deviceID: Identifier128, epochID: Identifier128, position: Int64, revokedAt: Int64)
        throws(OperationEnvelopeError)
    {
        guard position >= 0 else { throw .invalidField("roster.revocation.position") }
        self.deviceID = deviceID
        self.epochID = epochID
        self.position = position
        self.revokedAt = revokedAt
    }

    func canonicalValue() throws -> CanonicalValue {
        .object(
            try CanonicalObject([
                ("deviceID", .string(deviceID.hex)), ("epochID", .string(epochID.hex)),
                ("position", .integer(position)),
                ("revokedAt", .integer(revokedAt)),
            ]))
    }

    static func decode(_ value: CanonicalValue) throws -> RosterRevocation {
        var reader = try CanonicalFieldReader(value)
        let revocation = try RosterRevocation(
            deviceID: EnvelopeFields.identifier(reader.string("deviceID"), "roster.revocation.deviceID"),
            epochID: EnvelopeFields.identifier(reader.string("epochID"), "roster.revocation.epochID"),
            position: reader.integer("position"), revokedAt: reader.integer("revokedAt"))
        try reader.finish()
        return revocation
    }
}

/// An authorized TLS leaf pin: SHA-256 of the leaf's SubjectPublicKeyInfo, with the window in which it is accepted
/// (§8.1.4). The roster names the current pin and, during an overlap, the next one.
public struct TLSPin: Hashable, Sendable {
    public let spkiDigest: Digest256
    /// From when the pin is accepted, in Unix milliseconds.
    public let validFrom: Int64
    /// Until when, exclusive; none for an open window.
    public let validUntil: Int64?

    public init(spkiDigest: Digest256, validFrom: Int64, validUntil: Int64? = nil) throws(OperationEnvelopeError) {
        if let validUntil, validUntil <= validFrom { throw .invalidField("roster.tlsPins.window") }
        self.spkiDigest = spkiDigest
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    /// Whether the pin is accepted at `time`.
    public func isValid(at time: Int64) -> Bool { time >= validFrom && validUntil.map { time < $0 } ?? true }

    func canonicalValue() throws -> CanonicalValue {
        var fields: [(String, CanonicalValue)] = [("pin", .string(spkiDigest.hex)), ("validFrom", .integer(validFrom))]
        if let validUntil { fields.append(("validUntil", .integer(validUntil))) }
        return .object(try CanonicalObject(fields))
    }

    static func decode(_ value: CanonicalValue) throws -> TLSPin {
        var reader = try CanonicalFieldReader(value)
        let pin = try TLSPin(
            spkiDigest: EnvelopeFields.digest(reader.string("pin"), "roster.tlsPins.pin"),
            validFrom: reader.integer("validFrom"), validUntil: reader.optionalInteger("validUntil"))
        try reader.finish()
        return pin
    }
}

/// The roster's content, identified by (epoch, version).
public struct TrustRoster: Hashable, Sendable {
    public static let artifactType = "roster"
    public static let devicesPerPage = 64
    public static let revocationsPerPage = 256
    /// The most devices and revocations one roster lists.
    public static let maximumDevices = 1_024
    public static let maximumRevocations = 65_536
    public static let defaultNearbyTrustAgeDays: Int64 = 30

    public let datasetID: Identifier128
    public let epochID: Identifier128
    /// At least 1, raised by every change and every renewal.
    public let version: Int64
    public let issuedAt: Int64
    public let policyVersion: Int64
    public let maximumNearbyTrustAgeDays: Int64
    /// The current pin, then the next one during an overlap: one or two, distinct.
    public let tlsPins: [TLSPin]
    /// SHA-256 of the signed anchors bundle's body, in `ca` mode.
    public let anchorsDigest: Digest256?
    /// Core's export public key (P-256 key agreement), canonical SubjectPublicKeyInfo DER.
    public let exportKey: [UInt8]
    /// Strictly ascending by device ID.
    public let devices: [RosterDevice]
    /// Strictly ascending by device ID.
    public let revocations: [RosterRevocation]

    public init(
        datasetID: Identifier128, epochID: Identifier128, version: Int64, issuedAt: Int64, policyVersion: Int64,
        maximumNearbyTrustAgeDays: Int64 = TrustRoster.defaultNearbyTrustAgeDays, tlsPins: [TLSPin],
        anchorsDigest: Digest256?, exportKey: [UInt8], devices: [RosterDevice], revocations: [RosterRevocation]
    ) throws(OperationEnvelopeError) {
        guard version >= 1 else { throw .invalidField("roster.version") }
        guard policyVersion >= 0, (1...365).contains(maximumNearbyTrustAgeDays) else {
            throw .invalidField("roster.policy")
        }
        guard (1...2).contains(tlsPins.count), Set(tlsPins.map(\.spkiDigest)).count == tlsPins.count else {
            throw .invalidField("roster.tlsPins")
        }
        guard (1...256).contains(exportKey.count) else { throw .invalidField("roster.exportKey") }
        guard devices.count <= Self.maximumDevices, revocations.count <= Self.maximumRevocations,
            EnvelopeFields.isStrictlyAscending(devices.map(\.deviceID)),
            EnvelopeFields.isStrictlyAscending(revocations.map(\.deviceID))
        else { throw .invalidField("roster.entries") }
        // A listed device is revoked exactly when a revocation names it; a revocation may outlive the device's entry.
        let revoked = Set(revocations.map(\.deviceID))
        guard devices.allSatisfy({ ($0.status == .revoked) == revoked.contains($0.deviceID) }) else {
            throw .invalidField("roster.status")
        }
        self.datasetID = datasetID
        self.epochID = epochID
        self.version = version
        self.issuedAt = issuedAt
        self.policyVersion = policyVersion
        self.maximumNearbyTrustAgeDays = maximumNearbyTrustAgeDays
        self.tlsPins = tlsPins
        self.anchorsDigest = anchorsDigest
        self.exportKey = exportKey
        self.devices = devices
        self.revocations = revocations
    }

    public func device(_ id: Identifier128) -> RosterDevice? { devices.first { $0.deviceID == id } }

    /// Whether the roster revokes `id`, listed or not.
    public func isRevoked(_ id: Identifier128) -> Bool { revocations.contains { $0.deviceID == id } }

    /// The pins accepted at `time`.
    public func acceptedPins(at time: Int64) -> [Digest256] {
        tlsPins.filter { $0.isValid(at: time) }.map(\.spkiDigest)
    }

    // MARK: - Pages

    /// The ordered pages: the summary, then the device pages, then the revocation pages.
    public func pages() throws(OperationEnvelopeError) -> [[UInt8]] {
        do {
            var summary: [(String, CanonicalValue)] = [
                ("kind", .string("summary")), ("datasetID", .string(datasetID.hex)), ("epochID", .string(epochID.hex)),
                ("version", .integer(version)), ("issuedAt", .integer(issuedAt)),
                ("policyVersion", .integer(policyVersion)),
                ("maximumNearbyTrustAgeDays", .integer(maximumNearbyTrustAgeDays)),
                ("tlsPins", .array(try tlsPins.map { try $0.canonicalValue() })),
                ("exportKey", .string(StrictBase64URL.encode(exportKey))),
                ("deviceCount", .integer(Int64(devices.count))),
                ("revocationCount", .integer(Int64(revocations.count))),
            ]
            if let anchorsDigest { summary.append(("anchorsDigest", .string(anchorsDigest.hex))) }
            var pages = [try Self.encode(summary)]
            for start in stride(from: 0, to: devices.count, by: Self.devicesPerPage) {
                let slice = devices[start..<min(start + Self.devicesPerPage, devices.count)]
                pages.append(
                    try Self.encode([
                        ("kind", .string("devices")), ("devices", .array(try slice.map { try $0.canonicalValue() })),
                    ]))
            }
            for start in stride(from: 0, to: revocations.count, by: Self.revocationsPerPage) {
                let slice = revocations[start..<min(start + Self.revocationsPerPage, revocations.count)]
                pages.append(
                    try Self.encode([
                        ("kind", .string("revocations")),
                        ("revocations", .array(try slice.map { try $0.canonicalValue() })),
                    ]))
            }
            return pages
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("roster")
        }
    }

    /// The roster from its verified pages and header: the summary must agree with the header, and the pages must be
    /// exactly the summary, full device pages (the last may be partial), then full revocation pages likewise.
    public static func decode(pages: [[UInt8]], header: PagedArtifactHeader) throws(OperationEnvelopeError)
        -> TrustRoster
    {
        guard header.artifactType == artifactType, Int64(pages.count) == header.pageCount, let first = pages.first
        else { throw .invalidField("roster.pages") }
        do {
            var summary = try reader(first, kind: "summary")
            let datasetID = try EnvelopeFields.identifier(summary.string("datasetID"), "roster.datasetID")
            let epochID = try EnvelopeFields.identifier(summary.string("epochID"), "roster.epochID")
            let version = try summary.integer("version")
            guard datasetID == header.datasetID, epochID == header.epochID, version == header.version else {
                throw OperationEnvelopeError.invalidField("roster.header")
            }
            let issuedAt = try summary.integer("issuedAt")
            let policyVersion = try summary.integer("policyVersion")
            let nearbyAge = try summary.integer("maximumNearbyTrustAgeDays")
            let pins = try summary.array("tlsPins").map(TLSPin.decode)
            let exportKey = try summary.bytes("exportKey")
            let deviceCount = try summary.integer("deviceCount")
            let revocationCount = try summary.integer("revocationCount")
            let anchors = try summary.optionalString("anchorsDigest").map { hex throws in
                try EnvelopeFields.digest(hex, "roster.anchorsDigest")
            }
            try summary.finish()
            guard (0...Int64(maximumDevices)).contains(deviceCount),
                (0...Int64(maximumRevocations)).contains(revocationCount)
            else { throw OperationEnvelopeError.invalidField("roster.counts") }
            let devicePages = (Int(deviceCount) + devicesPerPage - 1) / devicesPerPage
            let revocationPages = (Int(revocationCount) + revocationsPerPage - 1) / revocationsPerPage
            guard pages.count == 1 + devicePages + revocationPages else {
                throw OperationEnvelopeError.invalidField("roster.pages")
            }
            var devices: [RosterDevice] = []
            for index in 0..<devicePages {
                var page = try reader(pages[1 + index], kind: "devices")
                let entries = try page.array("devices").map(RosterDevice.decode)
                try page.finish()
                let expected = min(devicesPerPage, Int(deviceCount) - index * devicesPerPage)
                guard entries.count == expected else { throw OperationEnvelopeError.invalidField("roster.devices") }
                devices += entries
            }
            var revocations: [RosterRevocation] = []
            for index in 0..<revocationPages {
                var page = try reader(pages[1 + devicePages + index], kind: "revocations")
                let entries = try page.array("revocations").map(RosterRevocation.decode)
                try page.finish()
                let expected = min(revocationsPerPage, Int(revocationCount) - index * revocationsPerPage)
                guard entries.count == expected else {
                    throw OperationEnvelopeError.invalidField("roster.revocations")
                }
                revocations += entries
            }
            return try TrustRoster(
                datasetID: datasetID, epochID: epochID, version: version, issuedAt: issuedAt,
                policyVersion: policyVersion, maximumNearbyTrustAgeDays: nearbyAge, tlsPins: pins,
                anchorsDigest: anchors, exportKey: exportKey, devices: devices, revocations: revocations)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch let error as CanonicalError {
            throw .encoding(error)
        } catch {
            throw .invalidField("roster")
        }
    }

    static func encode(_ fields: [(String, CanonicalValue)]) throws -> [UInt8] {
        try CanonicalEncoder.encode(
            .object(try CanonicalObject(fields)),
            limits: CanonicalLimits(maxBytes: PagedArtifactHeader.maximumPageBytes))
    }

    static func reader(_ page: [UInt8], kind: String) throws -> CanonicalFieldReader {
        var reader = try CanonicalFieldReader(
            CanonicalDecoder.decode(page, limits: CanonicalLimits(maxBytes: PagedArtifactHeader.maximumPageBytes)))
        guard try reader.string("kind") == kind else { throw OperationEnvelopeError.invalidField("roster.kind") }
        return reader
    }
}

/// A roster as it travels: the signed header and every page with its inclusion proof. Relays forward it unchanged.
public struct SignedRoster: Hashable, Sendable {
    public let headerBody: [UInt8]
    public let headerSignature: [UInt8]
    public let pages: [PagedArtifactPage]

    public init(headerBody: [UInt8], headerSignature: [UInt8], pages: [PagedArtifactPage])
        throws(OperationEnvelopeError)
    {
        guard headerSignature.count == 64 else { throw .invalidField("roster.signature") }
        guard !pages.isEmpty, pages.count <= 1 + 16 + 256 else { throw .invalidField("roster.pages") }
        self.headerBody = headerBody
        self.headerSignature = headerSignature
        self.pages = pages
    }

    /// The canonical wire object `{"header": {"body", "signature"}, "pages": [{"index", "bytes", "proof"}]}`.
    public func canonicalValue() throws(OperationEnvelopeError) -> CanonicalValue {
        do {
            let header = try CanonicalObject([
                ("body", .string(StrictBase64URL.encode(headerBody))),
                ("signature", .string(StrictBase64URL.encode(headerSignature))),
            ])
            let pages: [CanonicalValue] = try pages.map { page in
                .object(
                    try CanonicalObject([
                        ("index", .integer(page.index)), ("bytes", .string(StrictBase64URL.encode(page.bytes))),
                        ("proof", .array(page.proof.map { .string($0.hex) })),
                    ]))
            }
            return .object(try CanonicalObject([("header", .object(header)), ("pages", .array(pages))]))
        } catch {
            throw .invalidField("roster.wire")
        }
    }

    /// Decodes the wire object strictly; says nothing about who signed it.
    public static func decode(_ value: CanonicalValue) throws(OperationEnvelopeError) -> SignedRoster {
        do {
            var reader = try CanonicalFieldReader(value)
            var header = try CanonicalFieldReader(.object(try reader.object("header")))
            let body = try header.bytes("body")
            let signature = try header.bytes("signature")
            try header.finish()
            let pages = try reader.array("pages").map { value in
                var page = try CanonicalFieldReader(value)
                let proof = try page.array("proof").map { value in
                    guard case .string(let hex) = value else {
                        throw OperationEnvelopeError.invalidField("roster.proof")
                    }
                    return try EnvelopeFields.digest(hex, "roster.proof")
                }
                let decoded = try PagedArtifactPage(
                    index: page.integer("index"), bytes: page.bytes("bytes"), proof: proof)
                try page.finish()
                return decoded
            }
            try reader.finish()
            return try SignedRoster(headerBody: body, headerSignature: signature, pages: pages)
        } catch let error as OperationEnvelopeError {
            throw error
        } catch let error as CanonicalFieldError {
            throw .field(error)
        } catch {
            throw .invalidField("roster.wire")
        }
    }
}
