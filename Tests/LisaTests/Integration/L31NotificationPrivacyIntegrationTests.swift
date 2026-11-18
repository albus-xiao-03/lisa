// Integration tests for L31, notification privacy and authority at integration level (NOTIFY-02, NOTIFY-04, NOTIFY-06,
// NOTIFY-07, SEC-01, SEC-03, CALL-01; plan §6.7, §6.8; D-17, D-28, D-29, D-38): the pushes the real APNs adapter sends
// carry only generic localized text and opaque identifiers, plus a truncated title only for the device that opted in.
// After a whole device lifecycle — pairing, token updates, pushes signed with the provider key, a token APNs reports
// unregistered, and a removal — no device token, device credential, provider token or signing key appears in the logs,
// the export or any API answer, and dry-run pushes never record a token. A reminder nobody acknowledged never
// authorizes a call by itself: with calls disabled none is queued, and with calls enabled an earlier reminder counts
// only if one of its deliveries was accepted or presented. APNs is a scripted stand-in, the Mac's notification center
// is a scripted substitute, calls are dry runs, and every key, token and credential is synthetic.

import Foundation
import LisaAPIContract
import LisaClient
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaPorts
import Testing

@Suite("L31 — Notification privacy and authority (integration)", .tags(.integration))
struct L31NotificationPrivacyIntegrationTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// A synthetic title with private-looking details. None of its words can occur in hexadecimal identifiers.
    private let privateTitle = "Pay Dr. Example's invoice of $480 before the 5pm cutoff at the synthetic clinic"
    private let privateWords = ["Example", "invoice", "$480", "5pm", "clinic"]

    /// Brief availability is not notified, so a task's reminder is the only notification.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        return owner
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// The `aps.alert` dictionary of a push.
    private func alert(of push: ScriptedAPNsClient.Exchange) throws -> [String: Any] {
        let aps = try #require(try object(push.payload)["aps"] as? [String: Any])
        return try #require(aps["alert"] as? [String: Any])
    }

    /// Every file under the host's log directory, as text.
    private func logText(_ testHost: TestHost) throws -> String {
        let directory = testHost.dataDirectory.appendingPathComponent("logs")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names.contains("lisa.log"))
        return try names.map { name in
            try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        }.joined(separator: "\n")
    }

    @Test("Pushes carry only generic text and opaque identifiers, and a title only for the device that opted in")
    func pushPayloadsAreGeneric() async throws {
        try await ScratchDirectory.with { scratch in
            let live = try await LivePush()
            let center = ScriptedNotificationCenter()
            var testHost = TestHost(scratch: scratch, now: at("09:00"), owner: owner(), localNotifications: center)
            live.configure(&testHost)
            let host = try live.open(testHost)
            try TestHost.registerMac(on: host)
            let ownerClient = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            let phoneID = try await phone.pair(codeFrom: ownerClient)
            let padID = try await pad.pair(codeFrom: ownerClient)
            // Only the iPad opts in to item titles.
            let preferences = try await pad.client.notificationPreferences()
            #expect(!preferences.showTitles)
            _ = try await pad.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(expectedRevision: preferences.revision, showTitles: true))

            let task = try host.application.createTask(
                TaskDraft(title: privateTitle, deadline: SyntheticTask.due(at("09:30"))), by: .localOwner)
            await host.runtime.runOnce()
            let phoneToken = try #require(try LivePush.token(of: phoneID, in: host))
            let padToken = try #require(try LivePush.token(of: padID, in: host))
            let phonePush = try #require(live.apns.exchanges(to: phoneToken).first)
            let padPush = try #require(live.apns.exchanges(to: padToken).first)
            let notification = try #require(try TaskNotifications.occurrences(of: task.id, in: host).first)

            for push in [phonePush, padPush] {
                #expect(push.payload.count <= PushPayload.maxBytes)
                let payload = try object(push.payload)
                #expect(Set(payload.keys) == ["aps", "lisa"])
                let aps = try #require(payload["aps"] as? [String: Any])
                #expect(Set(aps.keys) == ["alert", "category", "thread-id", "sound", "interruption-level"])
                #expect(aps["category"] as? String == "LISA_REMINDER")
                #expect(aps["interruption-level"] as? String == "active")
                let thread = try #require(aps["thread-id"] as? String)
                #expect(thread.hasPrefix("reminder:"))
                #expect(thread.dropFirst("reminder:".count).allSatisfy { $0.isHexDigit || $0 == "-" })
                let lisa = try #require(payload["lisa"] as? [String: Any])
                #expect(Set(lisa.keys) == ["v", "kind", "notification", "subjectKind", "subject", "revision"])
                #expect(lisa["notification"] as? String == notification.id.rawValue)
                #expect(lisa["subjectKind"] as? String == "task")
                #expect(lisa["subject"] as? String == task.id.rawValue)
                // The headers carry the topic and opaque digests, never the item's text. The provider token in
                // `authorization` is signed base64url text, which is checked for secrets in another test.
                #expect(push.header("apns-topic") == SyntheticDevice.companionBundleID)
                let collapse = try #require(push.header("apns-collapse-id"))
                #expect(collapse.count == 32 && collapse.allSatisfy(\.isHexDigit))
                let headerText = push.request.headers.filter { $0.name.lowercased() != "authorization" }.map(\.value)
                    .joined(separator: " ")
                for word in privateWords {
                    #expect(!headerText.contains(word), "\(word) is in a header")
                }
            }

            // The iPhone, with default preferences, gets generic localized text only.
            let phoneAlert = try alert(of: phonePush)
            #expect(phoneAlert.count == 2)
            #expect(phoneAlert["title-loc-key"] as? String == "LISA_REMINDER_TITLE")
            #expect(phoneAlert["loc-key"] as? String == "LISA_REMINDER_BODY")
            let phoneText = String(decoding: phonePush.payload, as: UTF8.self)
            for word in privateWords {
                #expect(!phoneText.contains(word), "\(word) is in the default payload")
            }
            // The iPad, which opted in, gets the title as the only format argument, truncated to 60 characters.
            let padAlert = try alert(of: padPush)
            #expect(padAlert["loc-key"] as? String == "LISA_REMINDER_BODY_TITLED")
            let arguments = try #require(padAlert["loc-args"] as? [String])
            #expect(arguments.count == 1)
            let shown = try #require(arguments.first)
            #expect(shown.count <= 60)
            #expect(shown.hasSuffix("…"))
            #expect(privateTitle.hasPrefix(String(shown.dropLast())))
            // The Mac's own notification, with default preferences, has no title either.
            let local = try #require(center.presented.first)
            #expect(local.presentation.itemTitle == nil)
            #expect(local.presentation.bodyKey == "LISA_REMINDER_BODY")
            host.close()
        }
    }

    @Test("Tokens, credentials, provider tokens and the signing key never appear in logs, exports or API answers")
    func secretsNeverLeak() async throws {
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
            var tokens = [
                try #require(try LivePush.token(of: phoneID, in: host)),
                try #require(try LivePush.token(of: padID, in: host)),
            ]
            let credentials = [try #require(try phone.credential()), try #require(try pad.credential())]

            // The iPhone updates its token; the iPad's token is reported unregistered on the first push.
            let updated = SyntheticDevice.randomToken()
            _ = try await phone.client.registerPush(
                PushRegistrationRequest(
                    token: updated, environment: .development, topic: SyntheticDevice.companionBundleID))
            tokens.append(updated)
            live.apns.script(
                [.refused(status: 410, reason: "Unregistered", timestamp: at("09:00").addingTimeInterval(1))],
                forToken: tokens[1])
            testHost.advance(minutes: 1)
            _ = try host.application.createTask(
                TaskDraft(title: privateTitle, deadline: SyntheticTask.due(at("09:30"))), by: .localOwner)
            await host.runtime.runOnce()
            let padRecord = try host.application.record(DeviceRegistration.self, id: DeviceID(padID))
            #expect(padRecord?.pushToken?.state == .unregistered)
            try await ownerClient.removeDevice(id: padID)

            // The pushes did carry what APNs needs: the device token in the path and a signed provider token.
            #expect(live.apns.exchanges.map(\.deviceToken).sorted() == [tokens[1], updated].sorted())
            let authorization = try #require(live.apns.exchanges.first?.header("authorization"))
            #expect(authorization.hasPrefix("bearer "))
            let providerToken = String(authorization.dropFirst("bearer ".count))
            #expect(providerToken.split(separator: ".").count == 3)
            let keyLines = live.signingKey.split(separator: "\n").map(String.init).filter {
                !$0.hasPrefix("-----") && $0.count >= 16
            }
            #expect(!keyLines.isEmpty)
            let secrets = tokens + credentials + [providerToken, live.signingKey] + keyLines

            // Nothing secret is in the logs, which do record the lifecycle.
            let logs = try logText(testHost)
            #expect(logs.contains("device paired"))
            #expect(logs.contains("push token deactivated"))
            #expect(logs.contains(phoneID))
            // Nor in the export, the device list, health or the dry-run captures.
            let export = String(decoding: try await ownerClient.export(), as: UTF8.self)
            #expect(export.contains(phoneID))
            let listed = try await host.deviceTransport.send(
                APIExchange.request(.listDevices, credential: credentials[0]))
            #expect(listed.status == 200)
            let health = try await host.ownerTransport.send(APIExchange.request(.health))
            #expect(health.status == 200)
            let capturesFile = testHost.dataDirectory.appendingPathComponent("dry-run/captures.jsonl")
            let captures =
                FileManager.default.fileExists(atPath: capturesFile.path)
                ? try String(contentsOf: capturesFile, encoding: .utf8) : ""
            let places: [(String, String)] = [
                ("the logs", logs), ("the export", export),
                ("the device list", String(decoding: listed.body, as: UTF8.self)),
                ("health", String(decoding: health.body, as: UTF8.self)), ("the dry-run captures", captures),
            ]
            for (place, text) in places {
                for secret in secrets {
                    #expect(!text.contains(secret), "a secret value is in \(place)")
                }
            }
            host.close()
        }
    }

    @Test("Dry-run pushes record the intended notification, but never a device token")
    func dryRunPushesRecordNoToken() async throws {
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
            let tokens = [
                try #require(try LivePush.token(of: phoneID, in: host)),
                try #require(try LivePush.token(of: padID, in: host)),
            ]
            let task = try host.application.createTask(
                TaskDraft(title: privateTitle, deadline: SyntheticTask.due(at("09:30"))), by: .localOwner)
            await host.runtime.runOnce()

            let notification = try #require(try TaskNotifications.occurrences(of: task.id, in: host).first)
            let pushes = try host.recorder.recent(limit: 100).filter { $0.channel == .push }
            #expect(pushes.count == 2)
            for push in pushes {
                #expect(push.recipient == "apns development topic \(SyntheticDevice.companionBundleID)")
                #expect(push.content.contains("notification=\(notification.id.rawValue)"))
            }
            let file = try String(
                contentsOf: testHost.dataDirectory.appendingPathComponent("dry-run/captures.jsonl"), encoding: .utf8)
            #expect(file.contains(notification.id.rawValue))
            let logs = try logText(testHost)
            for token in tokens {
                #expect(!file.contains(token))
                #expect(!logs.contains(token))
            }
            for word in privateWords {
                #expect(!pushes.contains { $0.content.contains(word) }, "\(word) is in a dry-run push")
            }
            host.close()
        }
    }

    /// One way a reminder can go unacknowledged before an urgent deadline.
    struct CallCase: Sendable, CustomTestStringConvertible {
        var name: String
        var calls: CallSettings
        /// How the Mac's notification center answers every presentation of the task's reminders.
        var presentation: TransportResult
        var placesCall: Bool

        var testDescription: String { name }
    }

    static let callCases: [CallCase] = [
        CallCase(
            name: "calls disabled, as by default; every reminder presented", calls: CallSettings(),
            presentation: .accepted(providerReference: nil), placesCall: false),
        CallCase(
            name: "calls enabled; every presentation of the reminders refused",
            calls: CallSettings(enabled: true, approvedNumber: TestHost.ownerNumber),
            presentation: .rejected(
                reason: "the synthetic notification center refused it", invalidatesRecipient: false,
                providerTimestamp: nil),
            placesCall: false),
        CallCase(
            name: "calls enabled; every presentation's outcome unknown",
            calls: CallSettings(enabled: true, approvedNumber: TestHost.ownerNumber),
            presentation: .unknown(reason: "the synthetic notification center stopped answering"), placesCall: false),
        CallCase(
            name: "calls enabled; the reminders presented and left unacknowledged",
            calls: CallSettings(enabled: true, approvedNumber: TestHost.ownerNumber),
            presentation: .accepted(providerReference: nil), placesCall: true),
    ]

    @Test("An unacknowledged reminder alone never authorizes a call", arguments: callCases)
    func missingAcknowledgementAloneNeverCalls(_ callCase: CallCase) async throws {
        try await ScratchDirectory.with { scratch in
            var settings = owner()
            settings.calls = callCase.calls
            // Reminders an hour and ten minutes before the deadline: the second is inside the 15-minute urgency window.
            settings.reminders.deadlineOffsetsMinutes = [60, 10]
            let center = ScriptedNotificationCenter(otherwise: callCase.presentation)
            let testHost = TestHost(scratch: scratch, now: at("08:30"), owner: settings, localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try host.application.createTask(
                TaskDraft(
                    title: "Synthetic court filing", priority: .high, deadline: SyntheticTask.due(at("10:00"))),
                by: .localOwner)
            // 09:00 and 09:50: the reminders fire; 09:55: a queued call would be due.
            for time in ["09:00", "09:50", "09:55"] {
                testHost.clock.set(at(time))
                await host.runtime.runOnce()
            }
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 2)
            let reminders = try host.application.all(Reminder.self).filter { $0.subject == .task(task.id) }
            #expect(reminders.count == 2)
            #expect(reminders.allSatisfy { $0.state.name == "delivered" })

            let calls = try host.application.all(Delivery.self).filter { $0.channel == .call }
            let placed = try host.recorder.recent(limit: 100).filter { $0.channel == .call }
            if callCase.placesCall {
                #expect(placed.count == 1)
                #expect(calls.map(\.state) == [.capturedDryRun])
            } else if callCase.calls.enabled {
                #expect(placed.isEmpty)
                #expect(calls.map(\.state) == [.suppressed])
                #expect(
                    calls.first?.stateReason?.contains("no earlier reminder is outstanding without acknowledgement")
                        == true, "reason: \(calls.first?.stateReason ?? "none")")
            } else {
                #expect(placed.isEmpty)
                #expect(calls.isEmpty)
            }
            host.close()
        }
    }
}
