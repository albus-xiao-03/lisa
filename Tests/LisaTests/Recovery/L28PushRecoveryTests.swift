// Recovery tests for L28, push recovery (NOTIFY-03, REM-03, REM-04, NOTIFY-07; plan §6.4; D-26, D-36): pushes go
// through the real APNs adapter to scripted stand-ins for Apple's provider API, and the host restarts around them.
// A host that stops while a push is in flight records it as outcome unknown when it opens again and never resends
// it, while a push it had claimed but not yet sent is sent once; a push whose answer was lost after sending is
// recorded as unknown and never resent across restarts, while one that was provably not sent is retried and accepted
// once; and after downtime a push whose validity window passed is cancelled as expired instead of being sent late,
// while one still valid is sent once to every device. Devices pair with random tokens; nothing reaches Apple.

import Foundation
import LisaApplication
import LisaDomain
import LisaHTTP
import LisaHost
import LisaOwnerData
import LisaSecrets
import Testing

@Suite("L28 — Push recovery", .tags(.recovery))
struct L28PushRecoveryTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Brief availability is not notified, so the tasks' reminders are the only notifications.
    private func testHost(_ scratch: ScratchDirectory, at time: String, live: LivePush) -> TestHost {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        var testHost = TestHost(scratch: scratch, now: at(time), owner: owner)
        live.configure(&testHost)
        return testHost
    }

    /// Opens `testHost` with its push channel going through the real APNs adapter to `apns`.
    private func open(_ testHost: TestHost, live: LivePush, apns: any HTTPClient) throws -> LisaHost {
        let network = HostNetwork(
            makeHTTPClient: { purpose in
                if case .apns = purpose { return apns }
                throw TestHost.NetworkRefused(purpose: purpose)
            }, mailTrustStorePath: nil, library: TestHost.offlineNetwork.library)
        return try LisaHost.open(
            settings: testHost.settings,
            platform: HostPlatform(
                clock: testHost.clock,
                secrets: EnvironmentSecretStore(environment: [LivePush.signingKeyVariable: live.signingKey]),
                mode: "test", network: network))
    }

    /// Pairs a synthetic device of `deviceClass` with a random push token, as the companion does at pairing.
    private func pair(_ host: LisaHost, _ name: String, _ deviceClass: DeviceClass) throws -> (DeviceID, String) {
        let app = host.application
        let code = try app.createPairingCode(by: .localOwner)
        let issued = try app.pairDevice(
            code: code.code, installationID: SyntheticDevice.randomHex(bytes: 16), name: name, deviceClass: deviceClass,
            appBundleID: SyntheticDevice.companionBundleID, environment: .development)
        let token = SyntheticDevice.randomToken()
        let id = issued.registration.id
        _ = try app.registerPushToken(
            deviceID: id, token: token, environment: .development, topic: SyntheticDevice.companionBundleID)
        _ = try app.reportNotificationStatus(deviceID: id, authorization: .authorized, settings: [:])
        return (id, token)
    }

    /// A confirmed task due at `deadline`, created now. Every reminder offset has passed, so it gets one reminder now.
    private func dueTask(_ host: LisaHost, _ title: String, at deadline: String) throws -> LisaTask {
        try host.application.createTask(
            TaskDraft(title: title, deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    private func delivery(of task: LisaTask, to device: DeviceID, in host: LisaHost) throws -> Delivery? {
        try TaskNotifications.deliveries(of: task.id, in: host).first { $0.recipient == .device(device) }
    }

    @Test("A push in flight when the host stops is recorded as unknown and never resent; a claimed one is sent once")
    func crashAfterSubmission() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            let holding = HoldingHTTPClient(holding: 1, forwardingTo: live.apns)
            let testHost = testHost(scratch, at: "08:00", live: live)
            let crashed = try open(testHost, live: live, apns: holding)
            let (phone, phoneToken) = try pair(crashed, "Synthetic iPhone", .iPhone)
            let (pad, padToken) = try pair(crashed, "Synthetic iPad", .iPad)
            let task = try dueTask(crashed, "Synthetic contract", at: "08:40")
            #expect(try crashed.application.services.reminders.dispatchDue() == 1)
            let notification = try #require(try TaskNotifications.occurrences(of: task.id, in: crashed).first)

            // The worker claims both deliveries and submits the first push, which APNs has not answered yet.
            let inFlight = Task { try await crashed.application.services.outbox.runOnce() }
            #expect(try await holding.waitUntilHeld())
            let heldToken = try #require(holding.held.first?.url.lastPathComponent)
            let (stuck, stuckToken, other, otherToken) =
                heldToken == phoneToken ? (phone, phoneToken, pad, padToken) : (pad, padToken, phone, phoneToken)
            #expect(Set([phoneToken, padToken]).contains(heldToken))
            let submitting = try #require(try delivery(of: task, to: stuck, in: crashed))
            #expect(submitting.state == .inProgress && submitting.attempts.last?.phase == .submitting)
            let claimed = try #require(try delivery(of: task, to: other, in: crashed))
            #expect(claimed.state == .inProgress && claimed.attempts.last?.phase == .preparing)

            // The host stops with the push in flight and opens again once both leases have expired.
            crashed.close()
            testHost.advance(minutes: 5)
            var host = try open(testHost, live: live, apns: holding)
            #expect(host.recoveryNotes.contains("1 delivery attempt(s) had an unknown outcome and were not resent"))
            #expect(host.recoveryNotes.contains("1 interrupted delivery attempt(s) will be retried"))
            let unknown = try #require(try host.application.record(Delivery.self, id: submitting.id))
            #expect(unknown.state == .outcomeUnknown)
            #expect(unknown.stateReason == "the host stopped while the request was being submitted; it is not resent")

            for minutes in [1.0, 5, 30] {
                testHost.advance(minutes: minutes)
                await host.runtime.runOnce()
            }
            host.close()
            host = try open(testHost, live: live, apns: holding)
            testHost.advance(minutes: 10)
            await host.runtime.runOnce()

            let pushes = { (token: String) in live.apns.exchanges(to: token, about: notification.id.rawValue) }
            #expect(pushes(stuckToken).isEmpty)
            #expect(pushes(otherToken).map(\.wasAccepted) == [true])
            #expect(try host.application.record(Delivery.self, id: submitting.id)?.state == .outcomeUnknown)
            #expect(try delivery(of: task, to: other, in: host)?.state == .acceptedByProvider)
            let audited = try host.application.all(AuditEvent.self).filter {
                $0.affected.contains(submitting.id.rawValue)
            }
            #expect(audited.map(\.outcome) == [.failed])

            // APNs's late answer reaches only the stopped worker, which records nothing and sends nothing more.
            holding.release(
                with: .success(
                    HTTPResponse(
                        status: 200, headers: [HTTPHeader("apns-id", holding.held.first?.header("apns-id") ?? "")],
                        body: Data(), version: .http2, finalURL: holding.held[0].url)))
            _ = await inFlight.result
            #expect(try host.application.record(Delivery.self, id: submitting.id)?.state == .outcomeUnknown)
            #expect(pushes(stuckToken).isEmpty)
            #expect(pushes(otherToken).count == 1)
            #expect(holding.held.count == 1)
            host.close()
        }
    }

    @Test(
        "A push whose answer was lost after sending is never resent; one provably not sent is retried and accepted once"
    )
    func uncertainOutcomesAreNotRetried() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            let testHost = testHost(scratch, at: "08:00", live: live)
            var host = try live.open(testHost)
            let (phone, phoneToken) = try pair(host, "Synthetic iPhone", .iPhone)
            let (pad, padToken) = try pair(host, "Synthetic iPad", .iPad)
            live.apns.script([.failed(.timedOut(requestSent: true))], forToken: phoneToken)
            live.apns.script([.failed(.notSent("the connection was refused"))], forToken: padToken)
            let task = try dueTask(host, "Synthetic filing", at: "08:50")
            await host.runtime.runOnce()
            let notification = try #require(try TaskNotifications.occurrences(of: task.id, in: host).first)
            let unknown = try #require(try delivery(of: task, to: phone, in: host))
            #expect(unknown.state == .outcomeUnknown)
            #expect(unknown.stateReason?.contains("APNs may have received the notification") == true)
            #expect(unknown.stateReason?.hasSuffix("not resent automatically") == true)
            let retrying = try #require(try delivery(of: task, to: pad, in: host))
            #expect(retrying.state == .pending)
            #expect(retrying.stateReason?.hasPrefix("not sent:") == true)

            // Restarts in between change nothing about either decision.
            try live.restart(testHost, &host)
            for minutes in [2.0, 5, 10] {
                testHost.advance(minutes: minutes)
                await host.runtime.runOnce()
            }
            try live.restart(testHost, &host)
            testHost.advance(minutes: 10)
            await host.runtime.runOnce()

            let phonePushes = live.apns.exchanges(to: phoneToken, about: notification.id.rawValue)
            let padPushes = live.apns.exchanges(to: padToken, about: notification.id.rawValue)
            #expect(phonePushes.count == 1)
            #expect(padPushes.map(\.wasAccepted) == [false, true])
            // Every attempt of one delivery is the same notification for APNs.
            #expect(Set(padPushes.compactMap { $0.header("apns-id") }).count == 1)
            #expect(try host.application.record(Delivery.self, id: unknown.id)?.state == .outcomeUnknown)
            let accepted = try #require(try host.application.record(Delivery.self, id: retrying.id))
            #expect(accepted.state == .acceptedByProvider)
            #expect(accepted.attempts.count == 2)
            let audited = try host.application.all(AuditEvent.self).filter { $0.affected.contains(unknown.id.rawValue) }
            #expect(audited.map(\.outcome) == [.failed])
            host.close()
        }
    }

    @Test("After downtime, a push whose validity window passed is cancelled as expired, and a valid one is sent once")
    func downtimeExpiresStalePushes() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            let testHost = testHost(scratch, at: "06:30", live: live)
            var host = try live.open(testHost)
            let (_, phoneToken) = try pair(host, "Synthetic iPhone", .iPhone)
            let (_, padToken) = try pair(host, "Synthetic iPad", .iPad)
            // Quiet hours last until 07:00, so both reminders wait; one is valid until 07:25, the other until 07:10.
            let lasting = try dueTask(host, "Synthetic lasting deadline", at: "07:25")
            let fleeting = try dueTask(host, "Synthetic fleeting deadline", at: "07:10")
            await host.runtime.runOnce()
            let lastingNotification = try #require(try TaskNotifications.occurrences(of: lasting.id, in: host).first)
            let fleetingNotification = try #require(try TaskNotifications.occurrences(of: fleeting.id, in: host).first)
            #expect(try TaskNotifications.deliveries(of: lasting.id, in: host).allSatisfy { $0.state == .pending })
            #expect(live.apns.exchanges.isEmpty)

            // The host is down from 06:40 until 07:15, when it opens again and catches up.
            testHost.clock.set(at("06:40"))
            host.close()
            testHost.clock.set(at("07:15"))
            host = try live.open(testHost)
            await host.runtime.runOnce()
            testHost.advance(minutes: 5)
            await host.runtime.runOnce()
            try live.restart(testHost, &host)
            testHost.advance(minutes: 5)
            await host.runtime.runOnce()

            for token in [phoneToken, padToken] {
                #expect(
                    live.apns.exchanges(to: token, about: lastingNotification.id.rawValue).map(\.wasAccepted) == [true])
                #expect(live.apns.exchanges(to: token, about: fleetingNotification.id.rawValue).isEmpty)
            }
            let expired = try TaskNotifications.deliveries(of: fleeting.id, in: host).filter {
                $0.payload == .notification(fleetingNotification.id)
            }
            #expect(expired.count == 2)
            #expect(expired.allSatisfy { $0.state == .cancelled && $0.stateReason == "expired" })
            host.close()
        }
    }
}
