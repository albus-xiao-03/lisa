// Integration tests for L20, API authentication and permissions (API-01, API-03, NOTIFY-02, MEM-01; D-35), through
// the real router in process as docs/API.md documents them: a request without a device credential, with an unknown
// or malformed one, with a push token, or with a removed device's credential is a typed 401; a one-time pairing code
// works once within its 10 minutes, and five wrong codes discard every pending code; a paired device may read the
// day, capture, change ordinary preferences and remove itself, but may not create pairing codes, export, remove
// another device or change consequential preferences (403); each caller gets 300 requests a minute and
// unauthenticated pairing attempts a tenth of that, then 429 with Retry-After. Device registrations are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import Testing

@Suite("L20 — API authentication and permissions", .tags(.integration))
struct L20APIAuthenticationTests {
    private let start = TestTime.instant("2026-11-16T10:00", in: TestTime.newYork)

    private func pairing(_ code: String, installationID: String = SyntheticDevice.randomHex(bytes: 16)) throws
        -> APIRequest
    {
        let body = PairDeviceRequest(
            code: code, installationID: installationID, name: "Synthetic iPhone", deviceClass: .iPhone,
            appBundleID: SyntheticDevice.companionBundleID, environment: .development)
        return APIExchange.request(.pairDevice, body: try APIExchange.json(body), requestID: RequestID.random())
    }

    private func preferenceChange(_ key: String, _ value: PreferenceValueDTO, credential: String?) throws -> APIRequest
    {
        let body = PreferencesPatchRequest(changes: [PreferenceChange(key: key, value: value)])
        return APIExchange.request(
            .updatePreferences, body: try APIExchange.json(body), requestID: RequestID.random(), credential: credential)
    }

    @Test("Missing, unknown, malformed and revoked credentials, and push tokens, get a typed 401")
    func unauthenticatedRequestsAreRefused() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let devices = host.deviceTransport
            let owner = OwnerClient.inProcess(host)
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: devices, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: owner)
            let credential = try #require(try phone.credential())
            let token = SyntheticDevice.randomToken()
            _ = try await phone.client.registerPush(
                PushRegistrationRequest(
                    token: token, environment: .development, topic: SyntheticDevice.companionBundleID))
            #expect(try await devices.send(APIExchange.request(.listTasks, credential: credential)).status == 200)

            let refused = [
                APIExchange.request(.listTasks),
                APIExchange.request(.listTasks, credential: SyntheticDevice.randomHex(bytes: 32)),
                APIExchange.request(.listTasks, credential: token),
                APIRequest(method: .get, path: "/v1/tasks", headers: ["Authorization": "Basic \(credential)"]),
                APIRequest(method: .get, path: "/v1/tasks", headers: ["Authorization": "Bearer "]),
                APIExchange.request(
                    .capture, body: try APIExchange.json(CaptureRequestDTO(kind: .idea, text: "x", channel: .api)),
                    requestID: RequestID.random()),
            ]
            for request in refused {
                let response = try await devices.send(request)
                let body = APIExchange.expectError(response, .unauthenticated)
                #expect(body?.message.contains(credential) == false)
                #expect(body?.message.contains(token) == false)
            }
            #expect(try host.application.all(Capture.self).isEmpty)

            // Removing the device revokes its credential; the app then forgets its pairing but keeps its installation.
            let installation = try await phone.installationID()
            try await owner.removeDevice(id: phoneID)
            APIExchange.expectError(
                try await devices.send(APIExchange.request(.listTasks, credential: credential)), .unauthenticated)
            await #expect(throws: ClientError.self) { try await phone.client.tasks() }
            try phone.relaunch()
            let after = try await phone.client.installation()
            #expect(!after.isPaired)
            #expect(after.installationID == installation)
            host.close()
        }
    }

    @Test("A pairing code works once, within 10 minutes")
    func pairingCodeWorksOnceWithinItsLifetime() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let devices = host.deviceTransport
            let owner = OwnerClient.inProcess(host)

            let code = try await owner.createPairingCode()
            #expect(code.expiresAt == start.addingTimeInterval(600))
            testHost.advance(minutes: 9.9)
            let paired = try await devices.send(try pairing(code.code))
            #expect(paired.status == 201)
            let issued = try APIExchange.decode(PairDeviceResponse.self, paired)
            #expect(issued.credential.count >= 32)
            let listed = try await devices.send(APIExchange.request(.listDevices, credential: issued.credential))
            #expect(listed.status == 200)
            #expect(try APIExchange.decode([DeviceDTO].self, listed).map(\.id) == [issued.device.id])

            APIExchange.expectError(try await devices.send(try pairing(code.code)), .unauthenticated)

            let expiring = try await owner.createPairingCode()
            testHost.advance(minutes: 10.05)
            APIExchange.expectError(try await devices.send(try pairing(expiring.code)), .unauthenticated)
            #expect(try host.application.all(DeviceRegistration.self).count == 1)
            host.close()
        }
    }

    @Test("Five wrong pairing codes discard every pending code")
    func wrongCodesDiscardPendingCodes() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let devices = host.deviceTransport
            let owner = OwnerClient.inProcess(host)
            let first = try await owner.createPairingCode()
            let second = try await owner.createPairingCode()

            for _ in 1...4 {
                APIExchange.expectError(try await devices.send(try pairing("00000000")), .unauthenticated)
            }
            let fifth = try await devices.send(try pairing("00000000"))
            let body = APIExchange.expectError(fifth, .throttled)
            #expect((body?.retryAfterSeconds ?? 0) > 0)
            APIExchange.expectError(try await devices.send(try pairing(first.code)), .unauthenticated)
            APIExchange.expectError(try await devices.send(try pairing(second.code)), .unauthenticated)
            #expect(try host.application.all(DeviceRegistration.self).isEmpty)

            let fresh = try await owner.createPairingCode()
            #expect(try await devices.send(try pairing(fresh.code)).status == 201)
            host.close()
        }
    }

    @Test("A paired device may act on the owner's day but not on consequential or owner-only operations")
    func pairedDevicePermissions() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let devices = host.deviceTransport
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: devices, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: devices, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: owner)
            let padID = try await pad.pair(codeFrom: owner)
            let credential = try #require(try phone.credential())

            // Allowed: reading the day, capturing, an ordinary preference.
            #expect(try await devices.send(APIExchange.request(.rundown, credential: credential)).status == 200)
            let capture = APIExchange.request(
                .capture,
                body: try APIExchange.json(CaptureRequestDTO(kind: .idea, text: "Synthetic idea", channel: .api)),
                requestID: RequestID.random(), credential: credential)
            #expect(try await devices.send(capture).status == 201)
            #expect(
                try await devices.send(try preferenceChange("brief.targetWords", .number(300), credential: credential))
                    .status == 200)

            // Refused: pairing codes, export, removing another device, consequential preferences.
            let pairingCode = APIExchange.request(
                .createPairingCode, requestID: RequestID.random(), credential: credential)
            APIExchange.expectError(try await devices.send(pairingCode), .forbidden)
            APIExchange.expectError(
                try await devices.send(APIExchange.request(.export, credential: credential)), .forbidden)
            let removePad = APIExchange.request(
                .removeDevice(id: padID), requestID: RequestID.random(), credential: credential)
            APIExchange.expectError(try await devices.send(removePad), .forbidden)
            #expect(try await owner.devices().first { $0.id == padID }?.state == "active")
            let consequential: [(String, PreferenceValueDTO)] = [
                ("delivery.approvedEmailAddresses", .list(["someone@example.invalid"])),
                ("delivery.approvedPhoneNumber", .text("+15550199")), ("delivery.emailEnabled", .flag(false)),
                ("delivery.callsEnabled", .flag(true)), ("notifications.timeSensitive", .flag(true)),
                ("model.dataSharing", .text("full")),
            ]
            for (key, value) in consequential {
                APIExchange.expectError(
                    try await devices.send(try preferenceChange(key, value, credential: credential)), .forbidden)
            }
            let preferences = try await owner.preferences()
            #expect(preferences.map(\.key) == ["brief.targetWords"])

            // The owner may do all of these, and the device may remove itself.
            _ = try await owner.createPairingCode()
            _ = try await owner.export()
            #expect(
                try await host.ownerTransport.send(
                    try preferenceChange(
                        "delivery.approvedEmailAddresses", .list(["owner@example.com"]), credential: nil)
                ).status == 200)
            let removeSelf = APIExchange.request(
                .removeDevice(id: phoneID), requestID: RequestID.random(), credential: credential)
            #expect(try await devices.send(removeSelf).status == 200)
            APIExchange.expectError(
                try await devices.send(APIExchange.request(.listTasks, credential: credential)), .unauthenticated)
            host.close()
        }
    }

    @Test("Each caller gets 300 requests a minute, unauthenticated pairing a tenth, then 429 with Retry-After")
    func rateLimits() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: start)
            let host = try testHost.open()
            let devices = host.deviceTransport
            let owner = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: devices, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: devices, clock: testHost.clock)
            try await phone.pair(codeFrom: owner)
            try await pad.pair(codeFrom: owner)
            let phoneCredential = try #require(try phone.credential())
            let padCredential = try #require(try pad.credential())
            testHost.advance(minutes: 1)

            let read = APIExchange.request(.listTasks, query: ["limit": "1"], credential: phoneCredential)
            var admitted = 0
            for _ in 1...300 {
                if try await devices.send(read).status == 200 { admitted += 1 }
            }
            #expect(admitted == 300)
            let throttled = try await devices.send(read)
            let body = APIExchange.expectError(throttled, .throttled)
            #expect(body?.retryAfterSeconds == 60)
            #expect(throttled.header("Retry-After") == "60")
            // Other callers keep their own allowance.
            #expect(try await devices.send(APIExchange.request(.listTasks, credential: padCredential)).status == 200)
            _ = try await owner.tasks()
            testHost.advance(minutes: 1)
            #expect(try await devices.send(read).status == 200)

            // Unauthenticated pairing attempts get 30 a minute.
            for _ in 1...30 {
                APIExchange.expectError(try await devices.send(try pairing("00000000")), .unauthenticated)
            }
            let excess = APIExchange.expectError(try await devices.send(try pairing("00000000")), .throttled)
            #expect((excess?.retryAfterSeconds ?? 0) > 0)
            testHost.advance(minutes: 1)
            APIExchange.expectError(try await devices.send(try pairing("00000000")), .unauthenticated)
            host.close()
        }
    }
}
