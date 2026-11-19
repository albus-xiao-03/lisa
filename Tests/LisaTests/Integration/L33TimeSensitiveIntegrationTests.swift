// Integration tests for L33, Time Sensitive eligibility at integration level (NOTIFY-06, REM-02, CALL-01; plan §6.7;
// D-17, D-26, D-28, D-38): with the owner's opt-in, the deliveries the host actually makes — the Mac's notifications
// and the APNs pushes the real adapter sends — use the Time Sensitive level only for the reminder about an urgent
// confirmed deadline, and only on devices that allow it; ordinary reminders, overdue notices, important changes and
// the brief's availability stay at the standard level, as does everything without the opt-in. The classification
// bypasses nothing: an urgent reminder at night waits for the end of quiet hours or expires, a device that reports
// denial still gets nothing, failed attempts stop at the attempt limit, and no call is queued while calls are off. APNs
// is a scripted stand-in, the Mac's notification center a scripted substitute, and other pushes are dry runs.

import Foundation
import LisaAPIContract
import LisaDomain
import LisaHost
import LisaOwnerData
import Testing

@Suite("L33 — Time Sensitive eligibility (integration)", .tags(.integration))
struct L33TimeSensitiveIntegrationTests {
    private let event = SyntheticEvent(
        uid: "urgency-review@example.com", title: "Synthetic planning review", start: "2026-11-16T11:00",
        end: "2026-11-16T12:00")

    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Reminders ten minutes before a deadline, and an hour before when `hourAhead`; Time Sensitive for urgent
    /// deadlines only when `optedIn`; brief availability notified for the 07:30 brief when `briefNotifications`.
    private func owner(optedIn: Bool, hourAhead: Bool = true, briefNotifications: Bool = false) -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.timeSensitiveForUrgentDeadlines = optedIn
        owner.notifications.notifyBriefAvailability = briefNotifications
        owner.brief.deliveryTime = TestTime.time("07:30")
        owner.reminders.deadlineOffsetsMinutes = hourAhead ? [60, 10] : [10]
        return owner
    }

    private func cycle(_ host: LisaHost, _ testHost: TestHost, at time: String) async {
        testHost.clock.set(at(time))
        await host.runtime.runOnce()
    }

    private func task(_ title: String, priority: TaskPriority, due deadline: String, on host: LisaHost) throws
        -> LisaTask
    {
        try host.application.createTask(
            TaskDraft(title: title, priority: priority, deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    /// The reminder notification of `task` that fired at `time`.
    private func reminderNotification(of task: LisaTask, firedAt time: String, in host: LisaHost) throws
        -> NotificationIntent
    {
        try #require(
            try TaskNotifications.occurrences(of: task.id, in: host).first {
                $0.occurrenceKey.hasSuffix(":\(at(time).millisecondsSince1970)")
            })
    }

    private func level(of push: ScriptedAPNsClient.Exchange) throws -> String? {
        let payload = try #require(try JSONSerialization.jsonObject(with: push.payload) as? [String: Any])
        return (payload["aps"] as? [String: Any])?["interruption-level"] as? String
    }

    @Test("With the opt-in, only the reminder about an urgent confirmed deadline is Time Sensitive, where allowed")
    func onlyUrgentDeadlinesAreTimeSensitive() async throws {
        try await ScratchDirectory.with { scratch in
            let file = scratch.path("calendars", "work.ics")
            try SourceFiles.write(SyntheticEvent.calendar([event]), to: file, modifiedAt: at("07:00"))
            let live = try await LivePush()
            let center = ScriptedNotificationCenter()
            var testHost = TestHost(
                scratch: scratch, now: at("08:00"), owner: owner(optedIn: true, briefNotifications: true),
                sources: [SourceFiles.calendarSource(file)], localNotifications: center)
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
            let phoneToken = try #require(try LivePush.token(of: phoneID, in: host))
            let padToken = try #require(try LivePush.token(of: padID, in: host))
            // The iPad does not allow the Time Sensitive level.
            let padPreferences = try await pad.client.notificationPreferences()
            #expect(padPreferences.allowTimeSensitive)
            _ = try await pad.client.updateNotificationPreferences(
                DeviceNotificationPreferencesPatch(
                    expectedRevision: padPreferences.revision, allowTimeSensitive: false))

            // 08:00 the brief; 09:00 both tasks' reminders an hour ahead; 09:06 the event moves; 09:50 both tasks'
            // reminders ten minutes ahead; 10:05 both tasks are overdue.
            let urgent = try task("Synthetic court filing", priority: .high, due: "10:00", on: host)
            let ordinary = try task("Synthetic library return", priority: .normal, due: "10:00", on: host)
            await cycle(host, testHost, at: "08:00")
            await cycle(host, testHost, at: "09:00")
            var moved = event
            moved.start = "2026-11-16T11:30"
            moved.end = "2026-11-16T12:30"
            try SourceFiles.write(SyntheticEvent.calendar([moved]), to: file, modifiedAt: at("09:06"))
            await cycle(host, testHost, at: "09:06")
            await cycle(host, testHost, at: "09:50")
            await cycle(host, testHost, at: "10:05")

            let intents = try host.application.all(NotificationIntent.self)
            #expect(Set(intents.map(\.category)) == [.brief, .reminder, .commitmentChange, .overdue])
            let urgentReminder = try reminderNotification(of: urgent, firedAt: "09:50", in: host)
            #expect(urgentReminder.interruptionLevel == .timeSensitive)
            #expect(intents.filter { $0.interruptionLevel == .timeSensitive }.map(\.id) == [urgentReminder.id])
            let urgentRecord = try #require(
                try host.application.all(Reminder.self).first { urgentReminder.subject == .reminder($0.id) })
            #expect(urgentRecord.urgentDeadline)
            // The normal-priority deadline ten minutes ahead, and the urgent one an hour ahead, are ordinary reminders.
            #expect(try reminderNotification(of: ordinary, firedAt: "09:50", in: host).interruptionLevel == .active)
            #expect(try reminderNotification(of: urgent, firedAt: "09:00", in: host).interruptionLevel == .active)

            // What the devices were actually sent: the Mac's presentations and the APNs payloads.
            #expect(center.presented.count == intents.count)
            for presented in center.presented {
                let expected: InterruptionLevel =
                    presented.presentation.notificationID == urgentReminder.id.rawValue ? .timeSensitive : .active
                #expect(presented.presentation.level == expected, "\(presented.presentation.categoryIdentifier)")
            }
            let phonePushes = live.apns.exchanges(to: phoneToken)
            let padPushes = live.apns.exchanges(to: padToken)
            #expect(phonePushes.count == intents.count)
            #expect(padPushes.count == intents.count)
            for push in phonePushes {
                let urgentPush = push.lisa?.notificationID == urgentReminder.id.rawValue
                #expect(try level(of: push) == (urgentPush ? "time-sensitive" : "active"), "\(push.lisa?.kind ?? "")")
                if urgentPush { #expect(push.header("apns-priority") == "10") }
            }
            // The iPad, which opted out, gets even the urgent reminder at the standard level.
            for push in padPushes {
                #expect(try level(of: push) == "active", "\(push.lisa?.kind ?? "")")
            }
            // The brief only opens the app, so its push goes at the power-considered priority.
            let briefPush = try #require(phonePushes.first { $0.lisa?.kind == "brief" })
            #expect(briefPush.header("apns-priority") == "5")
            // Calls are off by default, and the Time Sensitive level does not change that.
            #expect(try host.application.all(Delivery.self).filter { $0.channel == .call }.isEmpty)
            host.close()
        }
    }

    @Test("Without the owner's opt-in, which is the default, the urgent reminder is delivered at the standard level")
    func standardLevelWithoutOptIn() async throws {
        try await ScratchDirectory.with { scratch in
            #expect(!NotificationSettings().timeSensitiveForUrgentDeadlines)
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(
                scratch: scratch, now: at("09:30"), owner: owner(optedIn: false), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            try await phone.pair(codeFrom: OwnerClient.inProcess(host))
            let urgent = try task("Synthetic court filing", priority: .high, due: "10:00", on: host)
            await cycle(host, testHost, at: "09:50")

            let reminder = try reminderNotification(of: urgent, firedAt: "09:50", in: host)
            #expect(reminder.interruptionLevel == .active)
            #expect(center.presented.map(\.presentation.level) == [.active])
            let pushes = try host.recorder.recent(limit: 100).filter { $0.channel == .push }
            #expect(pushes.count == 1)
            #expect(pushes.first?.content.contains("level=active") == true)
            #expect(pushes.first?.content.contains("level=timeSensitive") == false)
            host.close()
        }
    }

    @Test("A Time Sensitive reminder at night waits for the end of quiet hours, or expires, on every device")
    func timeSensitiveRespectsQuietHours() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(
                scratch: scratch, now: at("06:40"), owner: owner(optedIn: true, hourAhead: false),
                localNotifications: center)
            let host = try testHost.open()
            let mac = try TestHost.registerMac(on: host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let phoneID = DeviceID(try await phone.pair(codeFrom: OwnerClient.inProcess(host)))

            // Due 07:05: its urgent reminder at 06:55 can wait until quiet hours end at 07:00.
            // Due 06:58: its urgent reminder at 06:48 stops being valid before then, so it expires.
            let waits = try task("Synthetic early hearing", priority: .high, due: "07:05", on: host)
            let lapses = try task("Synthetic dawn deadline", priority: .high, due: "06:58", on: host)
            await cycle(host, testHost, at: "06:48")
            await cycle(host, testHost, at: "06:55")
            let waiting = try reminderNotification(of: waits, firedAt: "06:55", in: host)
            let lapsing = try reminderNotification(of: lapses, firedAt: "06:48", in: host)
            #expect(waiting.interruptionLevel == .timeSensitive)
            #expect(lapsing.interruptionLevel == .timeSensitive)
            for device in [mac, phoneID] {
                let deferred = try TaskNotifications.deliveries(of: waits.id, in: host).first {
                    $0.recipient == .device(device)
                }
                #expect(deferred?.state == .pending)
                #expect(deferred?.nextAttemptAt == at("07:00"))
                let expired = try TaskNotifications.deliveries(of: lapses.id, in: host).first {
                    $0.recipient == .device(device)
                }
                #expect(expired?.state == .cancelled)
                #expect(expired?.stateReason == "expired during quiet hours")
            }
            #expect(center.presented.isEmpty)
            #expect(try host.recorder.recent(limit: 100).filter { $0.channel == .push }.isEmpty)

            await cycle(host, testHost, at: "07:00")
            #expect(center.presented.map(\.presentation.notificationID) == [waiting.id.rawValue])
            #expect(center.presented.first?.presentation.level == .timeSensitive)
            let pushes = try host.recorder.recent(limit: 100).filter { $0.channel == .push }
            #expect(pushes.count == 1)
            #expect(pushes.first?.content.contains("notification=\(waiting.id.rawValue)") == true)
            #expect(TaskNotifications.presentations(of: lapses.id, center: center) == 0)
            host.close()
        }
    }

    @Test("A Time Sensitive reminder bypasses no recipient, attempt limit or call policy")
    func timeSensitiveBypassesNoLimit() async throws {
        try await ScratchDirectory.with { scratch in
            // The Mac's notification center is busy at every attempt.
            let center = ScriptedNotificationCenter(
                otherwise: .temporarilyUnavailable(reason: "the synthetic notification center is busy", retryAfter: nil)
            )
            var settings = owner(optedIn: true, hourAhead: false)
            settings.delivery.maxAttempts = 2
            let testHost = TestHost(scratch: scratch, now: at("13:30"), owner: settings, localNotifications: center)
            let host = try testHost.open()
            let mac = try TestHost.registerMac(on: host)
            let ownerClient = OwnerClient.inProcess(host)
            let phone = try SyntheticCompanion(
                "Synthetic iPhone", in: scratch, transport: host.deviceTransport, clock: testHost.clock)
            let pad = try SyntheticCompanion(
                "Synthetic iPad", deviceClass: .iPad, in: scratch, transport: host.deviceTransport,
                clock: testHost.clock)
            let phoneID = DeviceID(try await phone.pair(codeFrom: ownerClient))
            let padID = DeviceID(try await pad.pair(codeFrom: ownerClient))
            _ = try await pad.client.reportNotificationStatus(NotificationStatusRequest(authorization: .denied))

            let urgent = try task("Synthetic court filing", priority: .high, due: "14:00", on: host)
            await cycle(host, testHost, at: "13:50")
            let reminder = try reminderNotification(of: urgent, firedAt: "13:50", in: host)
            #expect(reminder.interruptionLevel == .timeSensitive)
            let deliveries = try TaskNotifications.deliveries(of: urgent.id, in: host)
            // A device that reports denial still gets nothing; the others are the recipients they always were.
            let denied = try #require(deliveries.first { $0.recipient == .device(padID) })
            #expect(denied.state == .suppressed)
            #expect(denied.stateReason == "the device reports notification permission as denied")
            #expect(deliveries.first { $0.recipient == .device(phoneID) }?.state == .capturedDryRun)
            #expect(Set(deliveries.map(\.recipient)) == [.device(mac), .device(phoneID), .device(padID)])

            // The Mac's failures are retried only up to the attempt limit.
            for time in ["13:51", "13:52", "13:53", "13:55"] {
                await cycle(host, testHost, at: time)
            }
            let failed = try #require(
                try TaskNotifications.deliveries(of: urgent.id, in: host).first {
                    $0.recipient == .device(mac)
                })
            #expect(failed.state == .failed)
            #expect(failed.attempts.count == 2)
            #expect(failed.stateReason?.contains("the attempt limit was reached") == true)
            #expect(TaskNotifications.presentations(of: urgent.id, center: center) == 2)
            // Calls stay off: the Time Sensitive level queues none.
            #expect(try host.application.all(Delivery.self).filter { $0.channel == .call }.isEmpty)
            #expect(try host.recorder.recent(limit: 100).filter { $0.channel == .call }.isEmpty)
            host.close()
        }
    }
}
