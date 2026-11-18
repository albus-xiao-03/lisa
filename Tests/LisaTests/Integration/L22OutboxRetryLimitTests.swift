// Integration tests for L22, limits at integration level (OPS-02, REM-03, NOTIFY-03; D-26): retry exhaustion in the
// delivery outbox stays bounded and visible. Repeated temporary failures stop at the configured attempt limit and
// leave a failed delivery with its reason in the outbox counts and the audit; a retry is never scheduled past the
// delivery's validity; and attempts interrupted by restarts count toward the limit, so a crash loop cannot retry
// forever. The notification center is a scripted substitute: nothing is shown.

import Foundation
import LisaApplication
import LisaDelivery
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaPorts
import LisaTime
import Testing

@Suite("L22 — Limits (integration)", .tags(.integration))
struct L22OutboxRetryLimitTests {
    private func at(_ time: String) -> Date {
        TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork)
    }

    /// Three attempts at most, retried after 15 to 60 seconds; brief availability is not notified.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.notifications.notifyBriefAvailability = false
        owner.delivery.maxAttempts = 3
        owner.delivery.baseBackoffSeconds = 30
        owner.delivery.maxBackoffSeconds = 60
        return owner
    }

    private func always(_ result: TransportResult) -> ScriptedNotificationCenter {
        ScriptedNotificationCenter(otherwise: result)
    }

    private let busy = TransportResult.temporarilyUnavailable(
        reason: "the notification service is busy", retryAfter: nil)

    /// A newly found commitment due at `deadline`: it gets one reminder at once.
    private func dueTask(_ host: LisaHost, at deadline: String) throws -> LisaTask {
        try host.application.createTask(
            TaskDraft(title: "Synthetic renewal", deadline: SyntheticTask.due(at(deadline))), by: .localOwner)
    }

    @Test("Repeated temporary failures stop at the attempt limit, and the failure stays visible")
    func retriesStopAtTheLimit() async throws {
        try await ScratchDirectory.with { scratch in
            let center = always(busy)
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "08:45")
            await host.runtime.runOnce()
            for _ in 0..<6 {
                testHost.advance(minutes: 61.0 / 60)
                await host.runtime.runOnce()
            }
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 3)
            let delivery = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(delivery.state == .failed)
            #expect(delivery.attempts.count == 3)
            #expect(delivery.stateReason?.contains("the attempt limit was reached") == true)
            #expect(try host.application.outboxCounts()[.failed] == 1)
            let audited = try host.application.all(AuditEvent.self).filter {
                $0.affected.contains(delivery.id.rawValue)
            }
            #expect(audited.map(\.outcome) == [.failed])
            host.close()
        }
    }

    @Test("A retry is never scheduled past the delivery's validity; the delivery fails instead")
    func retriesEndAtTheValidity() async throws {
        try await ScratchDirectory.with { scratch in
            let center = always(busy)
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            let host = try testHost.open()
            try TestHost.registerMac(on: host)
            // Due a minute from now, so the notification is valid only until 08:01.
            let task = try dueTask(host, at: "08:01")
            await host.runtime.runOnce()
            testHost.clock.set(at("08:00:40"))
            await host.runtime.runOnce()
            testHost.clock.set(at("08:02"))
            await host.runtime.runOnce()
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 2)
            let delivery = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(delivery.state == .failed)
            #expect(delivery.stateReason?.contains("no retry is possible before it expires") == true)
            host.close()
        }
    }

    @Test("Attempts interrupted by restarts count toward the limit, so a crash loop cannot retry forever")
    func crashLoopIsBounded() async throws {
        try await ScratchDirectory.with { scratch in
            let center = always(.accepted(providerReference: nil))
            let testHost = TestHost(scratch: scratch, now: at("08:00"), owner: owner(), localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let task = try dueTask(host, at: "08:45")
            #expect(try host.application.services.reminders.dispatchDue() == 1)
            // Each time, the host claims the delivery and stops before it is prepared; then it restarts.
            for _ in 0..<5 {
                _ = try host.application.services.outbox.claimDue()
                testHost.advance(minutes: 5)
                try testHost.restart(&host)
            }
            let delivery = try #require(try TaskNotifications.deliveries(of: task.id, in: host).first)
            #expect(delivery.attempts.count <= 3, "claimed \(delivery.attempts.count) times")
            #expect(delivery.state == .failed, "state: \(delivery.state), reason: \(delivery.stateReason ?? "none")")
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 0)
            host.close()
        }
    }
}
