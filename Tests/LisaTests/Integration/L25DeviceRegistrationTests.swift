// Integration tests for L25, device registration (NOTIFY-02, API-01, SEC-03; plan §6.3; D-29), through the real
// router in process and over loopback: an iPhone and an iPad pair separately, each with its own credential, of which
// the host keeps only a verifier, and each acts only for itself. A push token is accepted only from an authenticated
// registration, for its own app identifier and a configured environment, and is never returned. A token update
// replaces the old token, which stays only in bounded history, and later pushes go to the new token alone. An
// "unregistered" report from APNs deactivates a token only when it is newer than the token's registration, a bad
// token is deactivated at once, the registration shows that it needs a new token, and the app's next registration
// restores delivery. A reinstalled app pairs as a new registration, and the old one stops receiving once APNs reports
// its token or the owner removes it. Removing a device revokes its credential, deletes its token, cancels its pending
// deliveries and stops new ones. Pushes go through the real APNs adapter to a scripted stand-in for Apple, or are dry
// runs; device registrations and tokens are synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaCrypto
import LisaDevices
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L25 — Device registration", .tags(.integration))
struct L25DeviceRegistrationTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Brief availability is not notified, so a task's reminder is the only notification.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        return owner
    }

    private let companionTopic = SyntheticDevice.companionBundleID
    /// The Mac app's topic, which a host may also be configured to push to (a Mac app in client mode).
    private let macTopic = "com.example.lisa.mac"

    private func registration(_ id: String, in host: LisaHost) throws -> DeviceRegistration {
        try #require(try host.application.record(DeviceRegistration.self, id: DeviceID(id)))
    }

    /// A raw `PUT /v1/devices/current/push-registration`.
    private func pushRegistration(
        token: String, environment: APNsEnvironmentValue = .development, topic: String, credential: String?
    ) throws -> APIRequest {
        APIExchange.request(
            .pushRegistration,
            body: try APIExchange.json(PushRegistrationRequest(token: token, environment: environment, topic: topic)),
            requestID: RequestID.random(), credential: credential)
    }

    /// Pairs `companion` through the API with a one-time code from `owner`, without registering a push token.
    private func pairOnly(_ companion: SyntheticCompanion, owner: LisaAPIClient) async throws -> String {
        let code = try await owner.createPairingCode()
        let installation = try await companion.client.installation()
        return try await companion.client.pair(
            PairDeviceRequest(
                code: code.code, installationID: installation.installationID, name: companion.name,
                deviceClass: companion.deviceClass, appBundleID: companionTopic, environment: .development)
        ).id
    }

    /// A confirmed task due at `deadline`, created now. Its reminder offsets have passed, so it gets one reminder at
    /// once (a newly found commitment), which the next cycle delivers.
    private func dueTask(_ title: String, at deadline: String, on host: LisaHost) throws -> LisaTask {
        try host.application.createTask(
            TaskDraft(title: title, deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    /// The delivery of `task`'s reminder to `device`.
    private func delivery(of task: LisaTask, to device: String, in host: LisaHost) throws -> Delivery? {
        try TaskNotifications.deliveries(of: task.id, in: host).first { $0.recipient == .device(DeviceID(device)) }
    }

    @Test("An iPhone and an iPad pair separately, each with its own credential that acts only for itself")
    func separateRegistrationsHaveIndependentCredentials() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            let host = try testHost.open()
            let ownerClient = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: ownerClient)
            let padID = try await pad.pair(codeFrom: ownerClient)
            #expect(phoneID != padID)
            let phoneInstallation = try await phone.installationID()
            let padInstallation = try await pad.installationID()
            #expect(phoneInstallation != padInstallation)
            let phoneCredential = try #require(try phone.credential())
            let padCredential = try #require(try pad.credential())
            #expect(phoneCredential != padCredential)

            // The host keeps only a SHA-256 verifier of each credential, never the credential itself.
            let phoneRecord = try registration(phoneID, in: host)
            let padRecord = try registration(padID, in: host)
            #expect(phoneRecord.deviceClass == .iPhone)
            #expect(padRecord.deviceClass == .iPad)
            #expect(phoneRecord.installationID == phoneInstallation)
            #expect(phoneRecord.credentialVerifier == Digests.sha256Hex(phoneCredential))
            #expect(padRecord.credentialVerifier == Digests.sha256Hex(padCredential))
            #expect(!phoneRecord.credentialVerifier.contains(phoneCredential))
            #expect(try host.application.all(DeviceRegistration.self).count == 2)

            // Each credential acts only for its own registration.
            #expect(try await phone.client.devices().filter(\.isCurrent).map(\.id) == [phoneID])
            #expect(try await pad.client.devices().filter(\.isCurrent).map(\.id) == [padID])
            let padToken = SyntheticDevice.randomToken()
            _ = try await pad.client.registerPush(
                PushRegistrationRequest(token: padToken, environment: .development, topic: companionTopic))
            #expect(try LivePush.token(of: padID, in: host) == padToken)
            #expect(try LivePush.token(of: phoneID, in: host) != padToken)
            _ = try await phone.client.reportNotificationStatus(NotificationStatusRequest(authorization: .denied))
            #expect(try registration(padID, in: host).authorization == .authorized)

            // Revoking one registration leaves the other's credential working.
            try await ownerClient.removeDevice(id: padID)
            APIExchange.expectError(
                try await host.deviceTransport.send(APIExchange.request(.listDevices, credential: padCredential)),
                .unauthenticated)
            let stillPaired = try await host.deviceTransport.send(
                APIExchange.request(.listDevices, credential: phoneCredential))
            #expect(stillPaired.status == 200)
            host.close()
        }
    }

    @Test("A push token is accepted only from an authenticated registration, for a configured app and environment")
    func tokensNeedAnAuthenticatedRegistration() async throws {
        try await ScratchDirectory.with { scratch in
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            let host = try testHost.open()
            let devices = host.deviceTransport
            let ownerClient = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: devices, clock: testHost.clock)
            let phoneID = try await pairOnly(phone, owner: ownerClient)
            let credential = try #require(try phone.credential())
            let token = SyntheticDevice.randomToken()

            // Without an authenticated registration nothing is stored, whatever the token.
            let pendingCode = try await ownerClient.createPairingCode()
            for presented in [nil, SyntheticDevice.randomHex(bytes: 32), pendingCode.code, token] {
                let response = try await devices.send(
                    try pushRegistration(token: token, topic: companionTopic, credential: presented))
                APIExchange.expectError(response, .unauthenticated)
            }
            #expect(try registration(phoneID, in: host).pushToken == nil)

            // An authenticated registration is still refused for an unconfigured app or environment, or a token that
            // is not hexadecimal bytes.
            APIExchange.expectError(
                try await devices.send(
                    try pushRegistration(token: token, topic: "com.example.other", credential: credential)),
                .forbidden)
            APIExchange.expectError(
                try await devices.send(
                    try pushRegistration(
                        token: token, environment: .production, topic: companionTopic, credential: credential)),
                .forbidden)
            let malformed = [
                "", String(repeating: "zz", count: 32), String(token.dropLast()), String(repeating: "１２", count: 32),
                String(repeating: "ab", count: 513),
            ]
            for bad in malformed {
                APIExchange.expectError(
                    try await devices.send(
                        try pushRegistration(token: bad, topic: companionTopic, credential: credential)),
                    .invalidRequest, field: "token")
            }
            #expect(try registration(phoneID, in: host).pushToken == nil)

            // The registration's own app in a configured environment is accepted; the token is never returned.
            let accepted = try await devices.send(
                try pushRegistration(token: token, topic: companionTopic, credential: credential))
            #expect(accepted.status == 200)
            let device = try APIExchange.decode(DeviceDTO.self, accepted)
            #expect(device.id == phoneID)
            #expect(device.pushTokenState == "active")
            #expect(!String(decoding: accepted.body, as: UTF8.self).contains(token))
            let stored = try #require(try registration(phoneID, in: host).pushToken)
            #expect(stored.token.revealed == token)
            #expect(stored.topic == companionTopic)
            #expect(stored.environment == .development)
            let listed = try await devices.send(APIExchange.request(.listDevices, credential: credential))
            #expect(!String(decoding: listed.body, as: UTF8.self).contains(token))
            // The device can receive notifications once it also reports them allowed.
            let reported = try await phone.client.reportNotificationStatus(
                NotificationStatusRequest(authorization: .authorized))
            #expect(reported.canReceiveNotifications)
            host.close()
        }
    }

    @Test("A registration's push token is refused for another app's topic, even one the host is configured for")
    func tokensAreBoundToTheirOwnApp() async throws {
        try await ScratchDirectory.with { scratch in
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            // The host pushes to both apps: the companion, and the Mac app in client mode.
            testHost.settings.pushPolicy = PushRegistrationPolicy(
                allowedTopics: [companionTopic, macTopic], allowedEnvironments: [.development])
            let host = try testHost.open()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let phoneID = try await pairOnly(phone, owner: OwnerClient.inProcess(host))
            #expect(try registration(phoneID, in: host).appBundleID == companionTopic)
            let credential = try #require(try phone.credential())

            // The iPhone paired as the companion app, so a token for the Mac app's topic is not its own.
            let foreign = try await host.deviceTransport.send(
                try pushRegistration(token: SyntheticDevice.randomToken(), topic: macTopic, credential: credential))
            APIExchange.expectError(foreign, .forbidden)
            #expect(try registration(phoneID, in: host).pushToken == nil)
            let own = try await host.deviceTransport.send(
                try pushRegistration(
                    token: SyntheticDevice.randomToken(), topic: companionTopic, credential: credential))
            #expect(own.status == 200)
            #expect(try registration(phoneID, in: host).pushToken?.topic == companionTopic)
            host.close()
        }
    }

    @Test("A token update replaces the old token, keeps it only in bounded history, and later pushes use the new one")
    func tokenUpdatesReplaceTheOldToken() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            live.configure(&testHost)
            let host = try live.open(testHost)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let first = try #require(try LivePush.token(of: phoneID, in: host))
            let registrations = {
                try host.application.all(AuditEvent.self).filter {
                    $0.action == "device.push-token-registered" && $0.affected.contains(phoneID)
                }.count
            }
            #expect(try registrations() == 1)

            // The app registers its token again at every launch; the same token changes nothing.
            _ = try await phone.client.registerPush(
                PushRegistrationRequest(token: first, environment: .development, topic: companionTopic))
            #expect(try registrations() == 1)
            #expect(try registration(phoneID, in: host).tokenHistory.isEmpty)

            // A changed token replaces the old one, which is kept only as replaced history.
            testHost.advance(minutes: 1)
            let second = SyntheticDevice.randomToken()
            _ = try await phone.client.registerPush(
                PushRegistrationRequest(token: second, environment: .development, topic: companionTopic))
            let updated = try registration(phoneID, in: host)
            #expect(updated.pushToken?.token.revealed == second)
            #expect(updated.pushToken?.state == .active)
            #expect(updated.pushToken?.registeredAt == at("09:01"))
            #expect(updated.tokenHistory.map(\.token.revealed) == [first])
            #expect(updated.tokenHistory.map(\.state) == [.replaced])
            #expect(try registrations() == 2)

            // The next notification goes to the new token alone, at the development environment's endpoint.
            let task = try dueTask("Synthetic passport renewal", at: "09:30", on: host)
            await host.runtime.runOnce()
            #expect(live.apns.exchanges(to: first).isEmpty)
            let pushed = live.apns.exchanges(to: second)
            #expect(pushed.count == 1)
            #expect(pushed.first?.request.url.host == "api.sandbox.push.apple.com")
            #expect(pushed.first?.header("apns-topic") == companionTopic)
            #expect(try delivery(of: task, to: phoneID, in: host)?.state == .acceptedByProvider)

            // History is bounded: after six more updates only the five most recently replaced tokens remain.
            var replaced = [first, second]
            for _ in 0..<6 {
                let next = SyntheticDevice.randomToken()
                _ = try await phone.client.registerPush(
                    PushRegistrationRequest(token: next, environment: .development, topic: companionTopic))
                replaced.append(next)
            }
            let bounded = try registration(phoneID, in: host)
            #expect(bounded.pushToken?.token.revealed == replaced.last)
            #expect(bounded.tokenHistory.map(\.token.revealed) == Array(replaced.dropLast().reversed().prefix(5)))
            host.close()
        }
    }

    @Test("APNs feedback deactivates a token only when newer than its registration, and a new token restores delivery")
    func invalidTokensAreDeactivatedAndReplaced() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            live.configure(&testHost)
            let host = try live.open(testHost)
            let ownerClient = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: ownerClient)
            let padID = try await pad.pair(codeFrom: ownerClient)
            let phoneToken = try #require(try LivePush.token(of: phoneID, in: host))
            let padToken = try #require(try LivePush.token(of: padID, in: host))

            // An "unregistered" report older than the token's registration (09:00) is stale and changes nothing.
            live.apns.script(
                [.refused(status: 410, reason: "Unregistered", timestamp: at("08:00"))], forToken: phoneToken)
            let first = try dueTask("Synthetic first filing", at: "09:30", on: host)
            await host.runtime.runOnce()
            let stale = try #require(try delivery(of: first, to: phoneID, in: host))
            #expect(stale.state == .failed)
            #expect(stale.stateReason?.contains("410") == true)
            #expect(try registration(phoneID, in: host).pushToken?.state == .active)
            #expect(try delivery(of: first, to: padID, in: host)?.state == .acceptedByProvider)

            // A newer report deactivates the token; the registration shows that it needs a new token.
            testHost.advance(minutes: 5)
            live.apns.script(
                [.refused(status: 410, reason: "Unregistered", timestamp: at("09:05"))], forToken: phoneToken)
            _ = try dueTask("Synthetic second filing", at: "09:45", on: host)
            await host.runtime.runOnce()
            let deactivated = try registration(phoneID, in: host)
            #expect(deactivated.pushToken?.state == .unregistered)
            #expect(!deactivated.canReceiveNotifications)
            let listed = try #require(try await ownerClient.devices().first { $0.id == phoneID })
            #expect(listed.pushTokenState == "unregistered")
            #expect(!listed.canReceiveNotifications)
            #expect(
                try await ownerClient.health().deviceWarnings.contains("Synthetic iPhone: no active push registration"))
            #expect(
                try host.application.all(AuditEvent.self).contains {
                    $0.action == "device.push-token-deactivated" && $0.affected.contains(phoneID)
                })

            // Later notifications skip the iPhone with the reason recorded, and APNs's "bad device token" deactivates
            // the iPad's token at once.
            testHost.advance(minutes: 5)
            live.apns.script([.refused(status: 400, reason: "BadDeviceToken")], forToken: padToken)
            let third = try dueTask("Synthetic third filing", at: "10:00", on: host)
            await host.runtime.runOnce()
            let skipped = try #require(try delivery(of: third, to: phoneID, in: host))
            #expect(skipped.state == .suppressed)
            #expect(skipped.stateReason == "the device has no active push registration")
            #expect(live.apns.exchanges(to: phoneToken).count == 2)
            #expect(try delivery(of: third, to: padID, in: host)?.state == .failed)
            #expect(try registration(padID, in: host).pushToken?.state == .invalid)

            // At its next launch the iPhone registers a new token, and delivery resumes to it alone.
            testHost.advance(minutes: 5)
            let renewed = SyntheticDevice.randomToken()
            let reRegistered = try await phone.client.registerPush(
                PushRegistrationRequest(token: renewed, environment: .development, topic: companionTopic))
            #expect(reRegistered.pushTokenState == "active")
            #expect(reRegistered.canReceiveNotifications)
            let fourth = try dueTask("Synthetic fourth filing", at: "10:10", on: host)
            await host.runtime.runOnce()
            #expect(try delivery(of: fourth, to: phoneID, in: host)?.state == .acceptedByProvider)
            #expect(live.apns.exchanges(to: renewed).count == 1)
            #expect(live.apns.exchanges(to: phoneToken).count == 2)
            #expect(
                try delivery(of: fourth, to: padID, in: host)?.stateReason
                    == "the device has no active push registration")
            host.close()
        }
    }

    @Test(
        "A reinstalled app pairs anew, and the old registration stops receiving once APNs reports it or it is removed")
    func reinstallationPairsANewRegistration() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            live.configure(&testHost)
            let host = try live.open(testHost)
            let ownerClient = OwnerClient.inProcess(host)
            let installed = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let oldID = try await installed.pair(codeFrom: ownerClient)
            let oldCredential = try #require(try installed.credential())
            let oldToken = try #require(try LivePush.token(of: oldID, in: host))

            // The reinstalled app starts without the old identity, so it has a new installation and pairs again.
            testHost.advance(minutes: 1)
            let reinstalled = try SyntheticCompanion(
                "Synthetic iPhone reinstalled", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let newID = try await reinstalled.pair(codeFrom: ownerClient)
            #expect(newID != oldID)
            #expect(try await reinstalled.installationID() != (try await installed.installationID()))
            let newToken = try #require(try LivePush.token(of: newID, in: host))
            #expect(try registration(oldID, in: host).state == .active)

            // APNs reports the old installation's token unregistered: the old registration stops receiving.
            live.apns.script(
                [.refused(status: 410, reason: "Unregistered", timestamp: at("09:01"))], forToken: oldToken)
            let first = try dueTask("Synthetic first filing", at: "09:30", on: host)
            await host.runtime.runOnce()
            #expect(try delivery(of: first, to: newID, in: host)?.state == .acceptedByProvider)
            #expect(try registration(oldID, in: host).pushToken?.state == .unregistered)
            testHost.advance(minutes: 5)
            let second = try dueTask("Synthetic second filing", at: "09:45", on: host)
            await host.runtime.runOnce()
            #expect(try delivery(of: second, to: newID, in: host)?.state == .acceptedByProvider)
            #expect(try delivery(of: second, to: oldID, in: host)?.state == .suppressed)
            #expect(live.apns.exchanges(to: oldToken).count == 1)
            #expect(live.apns.exchanges(to: newToken).count == 2)

            // The owner removes the old registration: its credential stops working and it is no longer a warning.
            #expect(
                try await ownerClient.health().deviceWarnings.contains("Synthetic iPhone: no active push registration"))
            try await ownerClient.removeDevice(id: oldID)
            APIExchange.expectError(
                try await host.deviceTransport.send(APIExchange.request(.listDevices, credential: oldCredential)),
                .unauthenticated)
            #expect(try await ownerClient.health().deviceWarnings.isEmpty)
            #expect(try await reinstalled.client.devices().filter(\.isCurrent).map(\.id) == [newID])
            host.close()
        }
    }

    @Test(
        "Removing a device revokes its credential, deletes its token, cancels its pending deliveries and stops new ones"
    )
    func removalStopsDeliveries() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            let macID = try TestHost.registerMac(on: host)
            let ownerClient = OwnerClient.inProcess(host)
            var phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: ownerClient)
            let padID = try await pad.pair(codeFrom: ownerClient)
            let padCredential = try #require(try pad.credential())

            // The reminder is decided and recorded for every device, and nothing has been sent yet.
            let task = try dueTask("Synthetic visa appointment", at: "09:30", on: host)
            #expect(try host.application.services.reminders.dispatchDue() == 1)
            #expect(
                try TaskNotifications.deliveries(of: task.id, in: host).map(\.state) == [.pending, .pending, .pending])

            try await ownerClient.removeDevice(id: padID)
            let cancelled = try #require(try delivery(of: task, to: padID, in: host))
            #expect(cancelled.state == .cancelled)
            #expect(cancelled.stateReason == "the device was removed")
            let removed = try registration(padID, in: host)
            #expect(removed.state == .revoked)
            #expect(removed.pushToken == nil)
            #expect(removed.credentialVerifier != Digests.sha256Hex(padCredential))
            let listed = try #require(try await ownerClient.devices().first { $0.id == padID })
            #expect(listed.state == "revoked")
            #expect(listed.pushTokenState == nil)
            #expect(!listed.canReceiveNotifications)
            // Its next request is refused, and the app forgets its pairing.
            await #expect(throws: ClientError.self) { try await pad.client.devices() }
            #expect(try pad.credential() == nil)

            // The other devices still get the notification; the removed one gets nothing.
            await host.runtime.runOnce()
            #expect(try delivery(of: task, to: macID.rawValue, in: host)?.state == .acceptedByProvider)
            #expect(try delivery(of: task, to: phoneID, in: host)?.state == .capturedDryRun)
            #expect(try delivery(of: task, to: padID, in: host)?.state == .cancelled)
            #expect(try host.recorder.recent(limit: 100).filter { $0.channel == .push }.count == 1)
            let later = try dueTask("Synthetic consulate visit", at: "09:45", on: host)
            await host.runtime.runOnce()
            let laterRecipients = try TaskNotifications.deliveries(of: later.id, in: host).map(\.recipient)
            #expect(Set(laterRecipients) == [.device(macID), .device(DeviceID(phoneID))])

            // A device may also remove itself: its own pending delivery is cancelled the same way.
            testHost.advance(minutes: 5)
            let last = try dueTask("Synthetic embassy form", at: "10:00", on: host)
            #expect(try host.application.services.reminders.dispatchDue() == 1)
            try await phone.client.removeDevice(id: phoneID)
            #expect(try delivery(of: last, to: phoneID, in: host)?.state == .cancelled)
            #expect(try registration(phoneID, in: host).state == .revoked)
            try phone.relaunch()
            #expect(try await phone.client.installation().isPaired == false)
            host.close()
        }
    }

    @Test(
        "Over loopback, devices pair with separate credentials, register tokens, and a removed one is refused at once")
    func registrationOverLoopback() async throws {
        try await ScratchDirectory.with { scratch in
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner())
            testHost.settings.api = LoopbackAPIServer.settings()
            let host = try testHost.open()
            let server = try await LoopbackAPIServer.start(for: host)
            let phoneTransport = try server.deviceTransport()
            let padTransport = try server.deviceTransport()
            defer {
                phoneTransport.invalidate()
                padTransport.invalidate()
            }
            let ownerClient = try server.ownerClient()
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: phoneTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: padTransport, clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: ownerClient)
            let padID = try await pad.pair(codeFrom: ownerClient)
            #expect(try phone.credential() != (try pad.credential()))
            #expect(try LivePush.token(of: phoneID, in: host) != nil)
            #expect(try LivePush.token(of: padID, in: host) != nil)
            #expect(try await ownerClient.devices().map(\.canReceiveNotifications) == [true, true])

            // An unconfigured app is refused over the network as in process.
            do throws(ClientError) {
                _ = try await pad.client.registerPush(
                    PushRegistrationRequest(
                        token: SyntheticDevice.randomToken(), environment: .development, topic: "com.example.other"))
                Issue.record("a token for an unconfigured app was accepted")
            } catch {
                #expect(error.status == 403)
            }

            // The owner removes the iPad on the host; its next request is refused at once, the iPhone's is not.
            try await ownerClient.removeDevice(id: padID)
            do throws(ClientError) {
                _ = try await pad.client.devices()
                Issue.record("a removed device's request was accepted")
            } catch {
                #expect(error.isUnauthenticated)
            }
            #expect(try pad.credential() == nil)
            #expect(try await phone.client.devices().filter(\.isCurrent).map(\.id) == [phoneID])
            await server.stop()
            host.close()
        }
    }
}
