// Recovery tests for §16.3, a crash after delivery submission but before success is recorded (REM-03, REM-04,
// NOTIFY-03; D-26, D-36): the attempt is durably marked "submitting" before the transport is called; when the host
// stops while the submission is in flight, the reopened host records the outcome as unknown, says so, never resends
// it, and a late answer from the stopped worker cannot overwrite that record. The notification center is a scripted
// substitute that holds the submission in flight; nothing is shown.

import Foundation
import LisaApplication
import LisaDomain
import LisaHost
import LisaOwnerData
import LisaTime
import Testing

@Suite("§16.3 — Crash after delivery submission", .tags(.recovery))
struct CrashAfterSubmissionTests {
    @Test("A submission in flight when the host stops is recorded as outcome unknown and never resent")
    func submissionInFlightIsNotResent() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter(steps: [.hold])
            var owner = TestHost.owner()
            owner.notifications.notifyBriefAvailability = false
            let start = TestTime.instant("2026-11-16T08:00", in: TestTime.newYork)
            let testHost = TestHost(scratch: scratch, now: start, owner: owner, localNotifications: center)
            let crashed = try testHost.open()
            try TestHost.registerMac(on: crashed)
            // Every reminder offset has passed, so the newly found commitment gets one reminder now.
            let task = try crashed.application.createTask(
                TaskDraft(title: "Synthetic contract", deadline: SyntheticTask.due(start.addingTimeInterval(1800))),
                by: .localOwner)
            #expect(try crashed.application.services.reminders.dispatchDue() == 1)
            let inFlight = Task { try await crashed.application.services.outbox.runOnce() }
            // However the test ends, the held submission is answered, so no task is left waiting.
            defer { center.release(with: .accepted(providerReference: nil)) }
            #expect(try await center.waitUntilHeld())

            // The attempt was durably marked as submitting before the transport was called.
            let submitting = try #require(try TaskNotifications.deliveries(of: task.id, in: crashed).first)
            #expect(submitting.state == .inProgress)
            #expect(submitting.attempts.last?.phase == .submitting)

            // The host stops with the submission in flight, and opens again after the lease has expired.
            crashed.close()
            testHost.advance(minutes: 5)
            let host = try testHost.open()
            #expect(
                host.recoveryNotes.contains("1 delivery attempt(s) had an unknown outcome and were not resent"),
                "\(host.recoveryNotes)")
            let recovered = try #require(try host.application.record(Delivery.self, id: submitting.id))
            #expect(recovered.state == .outcomeUnknown)
            #expect(recovered.stateReason == "the host stopped while the request was being submitted; it is not resent")
            for _ in 0..<3 {
                testHost.advance(minutes: 2)
                await host.runtime.runOnce()
            }
            #expect(TaskNotifications.presentations(of: task.id, center: center) == 1)

            // The stopped worker's late answer is not recorded over the recovered outcome.
            center.release(with: .accepted(providerReference: nil))
            _ = try await inFlight.value
            #expect(try host.application.record(Delivery.self, id: submitting.id)?.state == .outcomeUnknown)
            #expect(try host.application.outboxCounts()[.outcomeUnknown] == 1)
            let audited = try host.application.all(AuditEvent.self).filter {
                $0.affected.contains(submitting.id.rawValue)
            }
            #expect(audited.map(\.outcome) == [.failed])
            host.close()
        }
    }
}
