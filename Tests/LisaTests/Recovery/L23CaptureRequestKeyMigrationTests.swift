// Recovery tests for L23, the capture request-key migration (DATA-02, API-03, IDEA-01; D-22, D-23, D-31, D-35): a
// database at schema version 3 holds captures written the way version 3 stored them, with the bare request ID in the
// unique `request_id` column, made by two paired devices and by the local owner. When the host opens it, it is copied
// aside and migrated to the latest schema, where the column names the caller as well (`<principal>:<request ID>`).
// Afterwards each caller's retry with its old request ID returns its own capture, while another caller using the same
// ID gets a new capture. The captures are older than the 30-day request record, so the capture itself answers.

import Foundation
import LisaAPIContract
import LisaClient
import LisaCrypto
import LisaDomain
import LisaHost
import LisaPorts
import LisaSQLite
import LisaStore
import Testing

@Suite("L23 — Capture request key migration", .tags(.recovery))
struct L23CaptureRequestKeyMigrationTests {
    private let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)

    /// A device paired under schema version 3, and the credential it holds.
    private struct LegacyDevice {
        var registration: DeviceRegistration
        var credential: String
        var id: DeviceID { registration.id }
    }

    /// A capture and the idea it made, as version 3 stored them.
    private struct LegacyCapture {
        var capture: Capture
        var idea: Idea
    }

    private func device(_ deviceClass: DeviceClass, name: String, pairedAt: Date) -> LegacyDevice {
        let credential = SyntheticDevice.randomHex(bytes: 32)
        var registration = DeviceRegistration(
            installationID: SyntheticDevice.randomHex(bytes: 16), name: name, deviceClass: deviceClass,
            appBundleID: SyntheticDevice.companionBundleID, environment: .development, transport: .apns,
            credentialVerifier: Digests.sha256Hex(credential), now: pairedAt)
        registration.authorization = .authorized
        return LegacyDevice(registration: registration, credential: credential)
    }

    private func capture(_ text: String, by principal: Principal, requestID: String?, at now: Date) -> LegacyCapture {
        var capture = Capture(
            kind: .idea, text: text, url: nil, channel: .api, principal: principal, requestID: requestID, now: now)
        let idea = Idea(originalCapture: text, captureID: capture.id, now: now)
        capture.resultingIdeaID = idea.id
        capture.processing = .processed
        return LegacyCapture(capture: capture, idea: idea)
    }

    /// Builds the version 3 schema at `path` with the first three migrations, then writes the records into its tables
    /// the way the store did then: the captures' `request_id` column holds the bare request ID.
    private func buildVersionThree(at path: String, devices: [LegacyDevice], captures: [LegacyCapture]) throws {
        let built = try LisaStorage.open(path: path, now: start, migrations: Array(Migrations.all.prefix(3)))
        #expect(built.migration.toVersion == 3)
        let database = try SQLiteDatabase(path: path)
        try database.writeTransaction { session in
            for device in devices { try insert(device.registration, into: session) }
            for legacy in captures {
                try insert(legacy.idea, into: session)
                try insert(
                    legacy.capture, into: session,
                    overriding: ["request_id": legacy.capture.requestID.map(SQLiteValue.text) ?? .null])
            }
        }
    }

    /// Inserts `entity` with its JSON body and indexed columns, with `overriding` in place of the current values.
    private func insert<E: StoredEntity>(
        _ entity: E, into session: SQLiteSession, overriding: [String: SQLiteValue] = [:]
    ) throws {
        let indexes = E.indexes.map(\.name)
        let values = entity.indexValues
        let body = String(decoding: try DomainJSON.encoder().encode(entity), as: UTF8.self)
        let indexed = indexes.map { name -> SQLiteValue in
            if let value = overriding[name] { return value }
            switch values[name] ?? .null {
            case .text(let text): return .text(text)
            case .integer(let number): return .integer(number)
            case .null: return .null
            }
        }
        let parameters: [SQLiteValue] =
            [
                .text(entity.id.description), .integer(entity.revision.value),
                .integer(entity.updatedAt.millisecondsSince1970), .text(body),
            ] + indexed
        let columns = (["id", "revision", "updated_at", "body"] + indexes).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: indexes.count + 4).joined(separator: ", ")
        _ = try session.query("INSERT INTO \(E.collectionName) (\(columns)) VALUES (\(placeholders))", parameters)
    }

    /// The stored `request_id` column of every capture, by capture ID.
    private func storedRequestKeys(at path: String, readOnly: Bool = false) throws -> [String: String?] {
        let database = try SQLiteDatabase(path: path, readOnly: readOnly, create: false)
        let rows = try database.perform { try $0.query("SELECT id, request_id FROM captures") }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0[0].text ?? "", $0[1].text) })
    }

    /// `POST /v1/captures` of an idea with `requestID`, as a device presenting `credential` or, without one, as the
    /// local owner in process.
    private func retry(
        _ text: String, requestID: String, credential: String?, on host: LisaHost
    ) async throws -> APIResponse {
        let request = APIExchange.request(
            .capture, body: try APIExchange.json(CaptureRequestDTO(kind: .idea, text: text, channel: .api)),
            requestID: requestID, credential: credential)
        if credential == nil { return try await host.ownerTransport.send(request) }
        return try await host.deviceTransport.send(request)
    }

    @Test("A version 3 database migrates its captures' request keys, and each caller's retry returns its own capture")
    func versionThreeCaptureKeysMigrate() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            try SourceFiles.directory(testHost.dataDirectory)
            let path = testHost.dataDirectory.appendingPathComponent("lisa.sqlite").path
            // Paired and captured 40 days ago, so the host's 30-day request records are long gone.
            let then = start.addingTimeInterval(-40 * 86_400)
            let phone = device(.iPhone, name: "Synthetic iPhone", pairedAt: then)
            let pad = device(.iPad, name: "Synthetic iPad", pairedAt: then)
            let phoneIdea = capture(
                "A synthetic idea from the phone", by: .pairedDevice(phone.id), requestID: "capture-phone-0001",
                at: then)
            let padIdea = capture(
                "A synthetic idea from the tablet", by: .pairedDevice(pad.id), requestID: "capture-pad-0001", at: then)
            let ownerIdea = capture(
                "A synthetic idea from the owner", by: .localOwner, requestID: "capture-owner-0001", at: then)
            let unkeyed = capture("A synthetic idea without a request ID", by: .localOwner, requestID: nil, at: then)
            try buildVersionThree(
                at: path, devices: [phone, pad], captures: [phoneIdea, padIdea, ownerIdea, unkeyed])
            #expect(
                try storedRequestKeys(at: path)[phoneIdea.capture.id.rawValue] == .some("capture-phone-0001"))

            let host = try testHost.open()
            let migration = host.storage.migration
            #expect(migration.fromVersion == 3)
            #expect(migration.toVersion == Migrations.latestVersion)
            let copy = try #require(migration.preMigrationBackup)
            // The pre-migration copy keeps the version 3 rows as they were.
            let copied = try SQLiteDatabase(path: copy, readOnly: true, create: false)
            #expect(try copied.perform { try $0.userVersion() } == 3)
            let copiedKeys = try storedRequestKeys(at: copy, readOnly: true)
            #expect(copiedKeys[padIdea.capture.id.rawValue] == .some("capture-pad-0001"))

            // The column now names the caller and the request ID; a capture without an ID stays without a key.
            let keys = try storedRequestKeys(at: path)
            #expect(keys[phoneIdea.capture.id.rawValue] == .some("device:\(phone.id.rawValue):capture-phone-0001"))
            #expect(keys[padIdea.capture.id.rawValue] == .some("device:\(pad.id.rawValue):capture-pad-0001"))
            #expect(keys[ownerIdea.capture.id.rawValue] == .some("local-owner:capture-owner-0001"))
            #expect(keys[unkeyed.capture.id.rawValue] == .some(nil))

            // Each caller's retry with its old ID returns its own capture, unchanged and not as a recorded replay.
            for (legacy, credential) in [
                (phoneIdea, Optional(phone.credential)), (padIdea, Optional(pad.credential)), (ownerIdea, nil),
            ] {
                let requestID = try #require(legacy.capture.requestID)
                let text = try #require(legacy.capture.text)
                let response = try await retry(text, requestID: requestID, credential: credential, on: host)
                #expect(response.status == 200, "\(requestID)")
                #expect(!APIExchange.isReplay(response))
                let answered = try APIExchange.decode(CaptureDTO.self, response)
                #expect(answered.id == legacy.capture.id.rawValue, "\(requestID)")
                #expect(answered.ideaID == legacy.idea.id.rawValue)
                #expect(!answered.created)
            }
            #expect(try host.application.all(Capture.self).count == 4)

            // Another caller using the same ID gets a new capture of its own.
            let crossed: [(String, String?, String)] = [
                ("capture-phone-0001", pad.credential, "device:\(pad.id.rawValue):capture-phone-0001"),
                ("capture-pad-0001", nil, "local-owner:capture-pad-0001"),
                ("capture-owner-0001", phone.credential, "device:\(phone.id.rawValue):capture-owner-0001"),
            ]
            var created: Set<String> = []
            for (requestID, credential, expectedKey) in crossed {
                let response = try await retry(
                    "A synthetic idea reusing \(requestID)", requestID: requestID, credential: credential, on: host)
                #expect(response.status == 201, "\(requestID)")
                let answered = try APIExchange.decode(CaptureDTO.self, response)
                #expect(answered.created)
                #expect(![phoneIdea, padIdea, ownerIdea].map(\.capture.id.rawValue).contains(answered.id))
                created.insert(answered.id)
                #expect(try storedRequestKeys(at: path)[answered.id] == .some(expectedKey))
            }
            #expect(created.count == 3)
            #expect(try host.application.all(Capture.self).count == 7)
            #expect(try host.application.all(Idea.self).count == 7)
            // The old captures are untouched.
            for legacy in [phoneIdea, padIdea, ownerIdea] {
                let stored = try #require(try host.application.record(Capture.self, id: legacy.capture.id))
                #expect(stored.text == legacy.capture.text)
                #expect(stored.principal == legacy.capture.principal)
                #expect(stored.revision == legacy.capture.revision)
            }
            host.close()
        }
    }
}
