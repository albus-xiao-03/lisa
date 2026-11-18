// Integration tests for L17, call policy at integration level (CALL-01, REM-01, REM-02, REM-03; D-17, D-26, D-28):
// the send-time gate in the delivery path, with the dry-run call channel. An urgent confirmed deadline queues a call
// five minutes after its reminder, and the call goes out only if every condition still holds when it is sent: calls
// enabled, the approved destination, an urgent confirmed commitment still open and unacknowledged, outside quiet hours
// and within the daily limits. Otherwise it is refused, and the refusal is recorded on the delivery and in the audit.

import Foundation
import LisaApplication
import LisaDelivery
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("L17 — Call policy (integration)", .tags(.integration))
struct L17CallGateIntegrationTests {
    private func at(_ iso: String) -> Date {
        TestTime.instant(iso, in: TestTime.newYork)
    }

    /// Calls enabled for the approved number (still a dry run), with reminders 60, 10 and 1 minutes before a deadline,
    /// so the 10-minute reminder falls inside the 15-minute urgency window.
    private func owner() -> OwnerSettings {
        var owner = TestHost.owner()
        owner.calls = CallSettings(enabled: true, approvedNumber: TestHost.ownerNumber)
        owner.reminders.deadlineOffsetsMinutes = [60, 10, 1]
        return owner
    }

    /// A host with a high-priority confirmed task due at `deadline`, run until its 10-minute reminder has fired and
    /// queued the call for five minutes later.
    private func queuedCall(
        _ scratch: ScratchDirectory, owner: OwnerSettings? = nil, deadline: String = "2026-11-16T10:00",
        priority: TaskPriority = .high
    ) async throws -> (TestHost, LisaHost, LisaTask) {
        let due = at(deadline)
        let testHost = TestHost(scratch: scratch, now: due.addingTimeInterval(-90 * 60), owner: owner ?? self.owner())
        let host = try testHost.open()
        let task = try host.application.createTask(
            TaskDraft(title: "Synthetic court filing", priority: priority, deadline: SyntheticTask.due(due)),
            by: .localOwner)
        for minutes in [60.0, 10.0] {
            testHost.clock.set(due.addingTimeInterval(-minutes * 60))
            await host.runtime.runOnce()
        }
        return (testHost, host, task)
    }

    private func calls(_ host: LisaHost) throws -> [Delivery] {
        try host.application.all(Delivery.self).filter { $0.channel == .call }
    }

    private func capturedCalls(_ host: LisaHost) throws -> [DryRunCapture] {
        try host.recorder.recent(limit: 100).filter { $0.channel == .call }
    }

    /// Runs the cycle at which the queued call is due (five minutes after the urgent reminder).
    private func sendTime(_ host: LisaHost, _ testHost: TestHost, deadline: String = "2026-11-16T10:00") async {
        testHost.clock.set(at(deadline).addingTimeInterval(-5 * 60))
        await host.runtime.runOnce()
    }

    /// The single call delivery was refused with `condition` among its reasons, and the refusal was audited.
    private func expectRefused(_ host: LisaHost, because condition: String) throws {
        let queued = try calls(host)
        #expect(queued.count == 1)
        let call = try #require(queued.first)
        #expect(call.state == .suppressed)
        #expect(call.stateReason?.contains(condition) == true, "reason: \(call.stateReason ?? "none")")
        #expect(try capturedCalls(host).isEmpty)
        let audited = try host.application.all(AuditEvent.self).filter {
            $0.action == "delivery.call" && $0.affected.contains(call.id.rawValue)
        }
        #expect(audited.map(\.outcome) == [.denied])
    }

    @Test("When every condition holds at send time, one call goes to the approved number after the grace period")
    func callPlacedWhenEveryConditionHolds() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, task) = try await queuedCall(scratch)
            let queued = try calls(host)
            #expect(queued.count == 1)
            #expect(queued.first?.recipient == .phoneNumber(TestHost.ownerNumber))
            #expect(queued.first?.nextAttemptAt == at("2026-11-16T09:55"))
            // Still inside the grace period: nothing is placed yet.
            testHost.clock.set(at("2026-11-16T09:52"))
            await host.runtime.runOnce()
            #expect(try capturedCalls(host).isEmpty)

            await sendTime(host, testHost)
            let captured = try capturedCalls(host)
            #expect(captured.count == 1)
            #expect(captured.first?.recipient.contains(TestHost.ownerNumber) == true)
            #expect(captured.first?.content.contains(task.title) == true)
            #expect(try calls(host).map(\.state) == [.capturedDryRun])
            host.close()
        }
    }

    @Test("Acknowledging the reminder during the grace period refuses the call")
    func acknowledgementRefusesTheCall() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, task) = try await queuedCall(scratch)
            let urgent = try #require(
                try host.application.all(Reminder.self).first {
                    $0.subject == .task(task.id) && $0.occurrenceKey.hasSuffix(":10")
                })
            testHost.clock.set(at("2026-11-16T09:52"))
            _ = try host.application.actOnReminder(.acknowledge, urgent.id, expectedRevision: nil, by: .localOwner)
            await sendTime(host, testHost)
            let call = try #require(try calls(host).first)
            #expect(call.state == .suppressed)
            #expect(call.stateReason == "acknowledged")
            #expect(try capturedCalls(host).isEmpty)
            #expect(try host.application.record(LisaTask.self, id: task.id)?.status == .open)
            host.close()
        }
    }

    @Test("A different approved number at send time refuses the queued call, and the refusal is recorded")
    func changedNumberRefusesTheCall() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, _) = try await queuedCall(scratch)
            testHost.clock.set(at("2026-11-16T09:52"))
            _ = try host.application.setPreference(
                .approvedPhoneNumber, .text("+15550111"), expectedRevision: nil, by: .localOwner)
            await sendTime(host, testHost)
            try expectRefused(host, because: "the destination is not the approved owner number")
            host.close()
        }
    }

    @Test("Calls turned off after the call was queued refuse it at send time")
    func callsDisabledRefusesTheCall() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, _) = try await queuedCall(scratch)
            testHost.clock.set(at("2026-11-16T09:52"))
            _ = try host.application.setPreference(.callsEnabled, .flag(false), expectedRevision: nil, by: .localOwner)
            await sendTime(host, testHost)
            try expectRefused(host, because: "calls are not enabled")
            host.close()
        }
    }

    @Test("A call due inside quiet hours is refused")
    func quietHoursRefuseTheCall() async throws {
        try await ScratchDirectory.with { scratch in
            let deadline = "2026-11-16T22:20"
            let (testHost, host, _) = try await queuedCall(scratch, deadline: deadline)
            await sendTime(host, testHost, deadline: deadline)
            try expectRefused(host, because: "quiet hours are in effect")
            host.close()
        }
    }

    @Test("Once the daily call limit is used, a further urgent deadline's call is refused")
    func dailyLimitRefusesFurtherCalls() async throws {
        try await ScratchDirectory.with { scratch in
            var limited = owner()
            limited.calls.maxCallsPerDay = 1
            let (testHost, host, _) = try await queuedCall(scratch, owner: limited)
            let second = try host.application.createTask(
                TaskDraft(
                    title: "Synthetic second filing", priority: .high,
                    deadline: SyntheticTask.due(at("2026-11-16T11:00"))),
                by: .localOwner)
            await sendTime(host, testHost)
            #expect(try capturedCalls(host).count == 1)
            for time in ["2026-11-16T10:00", "2026-11-16T10:50", "2026-11-16T10:55"] {
                testHost.clock.set(at(time))
                await host.runtime.runOnce()
            }
            let refused = try calls(host).filter { $0.idempotencyKey.contains(second.id.rawValue) }
            #expect(refused.count == 1)
            #expect(refused.first?.state == .suppressed)
            #expect(refused.first?.stateReason?.contains("the daily call limit is reached") == true)
            #expect(try capturedCalls(host).count == 1)
            host.close()
        }
    }

    @Test("Completing the task before the call is due suppresses the call")
    func completionSuppressesTheCall() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, task) = try await queuedCall(scratch)
            testHost.clock.set(at("2026-11-16T09:52"))
            _ = try host.application.setTaskStatus(task.id, to: .completed, expectedRevision: nil, by: .localOwner)
            await sendTime(host, testHost)
            #expect(try calls(host).map(\.state) == [.suppressed])
            #expect(try capturedCalls(host).isEmpty)
            host.close()
        }
    }

    @Test("A normal-priority deadline never queues a call, however close it is")
    func normalPriorityNeverCalls() async throws {
        try await ScratchDirectory.with { scratch in
            let (testHost, host, _) = try await queuedCall(scratch, priority: .normal)
            await sendTime(host, testHost)
            #expect(try calls(host).isEmpty)
            #expect(try capturedCalls(host).isEmpty)
            host.close()
        }
    }
}
