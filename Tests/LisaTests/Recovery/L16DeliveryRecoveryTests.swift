// Recovery tests for L16, delivery recovery (REM-03, REM-04, NOTIFY-03, EMAIL-01; D-26, D-36): restarts and
// uncertain provider outcomes never cause blind duplicate sending. A notification deferred by quiet hours survives a
// restart and is presented once when they end, or expires if it is no longer valid by then; an unknown outcome is
// recorded and never resent; temporary failures and throttling are retried within their backoff and retry-after
// times until accepted, then never again; and a delivery claimed when the host stopped is retried once. The
// notification center is a scripted substitute and email is a dry run: nothing is sent anywhere.

import Foundation
import LisaApplication
import LisaDelivery
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaPorts
import LisaTime
import Testing

@Suite("L16 — Delivery recovery", .tags(.recovery))
struct L16DeliveryRecoveryTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Reminders are also emailed to the approved address; brief availability is not notified, so the only
    /// notifications are the tasks' reminders; retries back off between 15 and 60 seconds.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.reminders.emailReminders = true
        owner.notifications.notifyBriefAvailability = false
        owner.delivery.baseBackoffSeconds = 30
        owner.delivery.maxBackoffSeconds = 60
        return owner
    }

    /// A confirmed task due at `deadline`, created now. Every reminder offset has passed, so it gets one reminder at
    /// once (a newly found commitment).
    private func dueTask(_ host: LisaHost, at deadline: String) throws -> LisaTask {
        try host.application.createTask(
            TaskDraft(title: "Synthetic signature", deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    private func cycle(_ host: LisaHost, _ testHost: TestHost, at time: String) async {
        testHost.clock.set(at(time))
        await host.runtime.runOnce()
    }

    @Test("A notification deferred by quiet hours survives a restart and is presented once when they end")
    func deferredNotificationSurvivesRestart() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("06:30"), owner: owner(), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "07:20")
            await cycle(host, testHost, at: "06:30")
            let deferred = try TaskNotifications.deliveries(of: task.id, in: host)
            #expect(deferred.count == 1)
            #expect(deferred.first?.state == .pending)
            #expect(deferred.first?.nextAttemptAt == at("07:00"))
            #expect(deferred.first?.stateReason == "deferred until quiet hours end")
            #expect(deferred.first?.attempts.isEmpty == true)
            // Email is not an interruption: its copy is not held for quiet hours.
            #expect(try TaskNotifications.emails(of: task.id, in: host).map(\.state) == [.capturedDryRun])

            try testHost.restart(&host)
            await cycle(host, testHost, at: "06:45")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 0)
            await cycle(host, testHost, at: "07:00")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)
            try testHost.restart(&host)
            await cycle(host, testHost, at: "07:05")
            await cycle(host, testHost, at: "07:10")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)
            #expect(try TaskNotifications.deliveries(of: task.id, in: host).map(\.state) == [.acceptedByProvider])
            let emailed = try host.recorder.recent(limit: 100).filter {
                $0.channel == .email && $0.subject?.hasPrefix("Reminder") == true
            }
            #expect(emailed.count == 1)
            host.close()
        }
    }

    @Test("A notification that would expire before quiet hours end is cancelled, not sent late")
    func notificationExpiringInQuietHoursIsCancelled() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("06:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "06:50")
            await cycle(host, testHost, at: "06:00")
            await cycle(host, testHost, at: "07:00")
            let deliveries = try TaskNotifications.deliveries(of: task.id, in: host)
            #expect(deliveries.map(\.state) == [.cancelled])
            #expect(deliveries.first?.stateReason == "expired during quiet hours")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 0)
            host.close()
        }
    }

    @Test("An unknown provider outcome is recorded and never resent, across restarts")
    func unknownOutcomeIsNeverResent() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter(steps: [
                .answer(.unknown(reason: "the connection closed after the request was sent"))
            ])
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "08:30")
            await cycle(host, testHost, at: "08:00")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)
            for time in ["08:05", "08:10"] {
                try testHost.restart(&host)
                await cycle(host, testHost, at: time)
            }
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)
            let delivery = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(delivery.state == .outcomeUnknown)
            #expect(delivery.stateReason?.contains("not resent automatically") == true)
            #expect(delivery.attempts.count == 1)
            #expect(try host.application.outboxCounts()[.outcomeUnknown] == 1)
            let audited = try host.application.all(AuditEvent.self).filter {
                $0.action == "delivery.localNotification" && $0.affected.contains(delivery.id.rawValue)
            }
            #expect(audited.map(\.outcome) == [.failed])
            host.close()
        }
    }

    @Test("Temporary failures and throttling are retried within backoff and retry-after until accepted, then never")
    func retriesUntilAcceptedThenStop() async throws {
        try await ScratchDirectory.with { scratch in
            let retryAfter = at("08:02:30")
            let center = ScriptedNotificationCenter(steps: [
                .answer(.temporarilyUnavailable(reason: "the notification service is busy", retryAfter: nil)),
                .answer(.throttled(retryAfter: retryAfter)),
                .answer(.notSent(reason: "the connection was refused")),
            ])
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "08:30")
            let presented = { TaskNotifications.presentations(of: task.id, center: center) }
            await cycle(host, testHost, at: "08:00")
            #expect(presented() == 1)
            try testHost.restart(&host)
            await cycle(host, testHost, at: "08:01:01")
            #expect(presented() == 2)
            // Throttled until 08:02:30: a cycle before that sends nothing.
            await cycle(host, testHost, at: "08:02:02")
            #expect(presented() == 2)
            #expect(try TaskNotifications.deliveries(of: task.id, in: host).first?.nextAttemptAt == retryAfter)
            await cycle(host, testHost, at: "08:03:03")
            #expect(presented() == 3)
            await cycle(host, testHost, at: "08:04:04")
            #expect(presented() == 4)
            try testHost.restart(&host)
            await cycle(host, testHost, at: "08:06")
            await cycle(host, testHost, at: "08:10")
            #expect(presented() == 4)
            let delivery = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(delivery.state == .acceptedByProvider)
            #expect(delivery.attempts.count == 4)
            host.close()
        }
    }

    @Test("A delivery claimed when the host stopped, before anything was submitted, is retried once after a restart")
    func claimedBeforeSubmissionIsRetriedOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "08:30")
            // The cycle decides the reminder and claims its delivery, and the host stops before preparing it.
            #expect(try host.application.services.reminders.dispatchDue() == 1)
            let claimed = try host.application.services.outbox.claimDue()
            #expect(claimed.map(\.channel).contains(.localNotification))
            testHost.advance(minutes: 5)
            try testHost.restart(&host)
            #expect(host.recoveryNotes.contains { $0.contains("will be retried") })
            let recovered = try #require(
                try TaskNotifications.deliveries(of: task.id, in: host).first { $0.channel == .localNotification })
            #expect(recovered.state == .pending)
            #expect(recovered.attempts.map(\.result) == ["lease expired before submission"])
            await host.runtime.runOnce()
            testHost.advance(minutes: 5)
            await host.runtime.runOnce()
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)
            let delivered = try #require(try host.application.record(Delivery.self, id: recovered.id))
            #expect(delivered.state == .acceptedByProvider)
            #expect(delivered.attempts.count == 2)
            host.close()
        }
    }
}
