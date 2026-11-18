// Recovery tests for §16.3, two simultaneous brief requests (BRIEF-03, NOTIFY-01, EMAIL-01, API-01; D-18, D-27,
// D-35): on-demand requests through the API and the scheduled dispatch, all at the same moment, leave one canonical
// brief for the day with explicit versions, and the day's brief is delivered once: one notification per device and one
// email to the approved address, also after a restart.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDomain
import LisaHost
import LisaTime
import Testing

@Suite("§16.3 — Two simultaneous brief requests", .tags(.recovery))
struct SimultaneousBriefRequestsTests {
    private let today = TestTime.date("2026-11-16")

    @Test("Simultaneous requests give one daily brief, one notification per device and one email")
    func simultaneousRequestsDeliverOnce() async throws {
        try await ScratchDirectory.with { scratch in
            let center = ScriptedNotificationCenter()
            // 06:30 is the brief time.
            let testHost = TestHost(
                scratch: scratch, now: TestTime.instant("2026-11-16T06:30", in: TestTime.newYork),
                localNotifications: center)
            var host = try testHost.open()
            try TestHost.registerMac(on: host)
            let transport = host.ownerTransport
            let briefs = host.application.services.briefs
            let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
                for name in ["siri", "app"] {
                    group.addTask {
                        try await transport.send(
                            APIRequest(
                                method: .post, path: APIRoute.regenerateBrief.path,
                                headers: [APIVersioning.requestIDHeader: "brief-request-\(name)"])
                        ).status
                    }
                }
                for _ in 0..<2 {
                    group.addTask {
                        _ = try briefs.dispatchIfDue()
                        return 200
                    }
                }
                var collected: [Int] = []
                for try await status in group { collected.append(status) }
                return collected
            }
            #expect(statuses == [200, 200, 200, 200])

            await host.runtime.runOnce()
            try testHost.restart(&host)
            // 06:30 is inside quiet hours, so the notification waits for 07:00.
            for time in ["2026-11-16T06:35", "2026-11-16T07:00", "2026-11-16T07:05"] {
                testHost.clock.set(TestTime.instant(time, in: TestTime.newYork))
                await host.runtime.runOnce()
            }

            let stored = try host.application.all(Brief.self).filter { $0.localDate == today }
            #expect(stored.count == 1)
            #expect((1...4).contains(stored.first?.version ?? 0))
            let dispatched = try host.application.all(NotificationIntent.self).filter { $0.category == .brief }
            #expect(dispatched.count == 1)
            #expect(center.presented.filter { $0.presentation.categoryIdentifier == "LISA_BRIEF" }.count == 1)
            let emails = try host.recorder.recent(limit: 100).filter {
                $0.subject?.hasPrefix("Your Lisa brief") == true
            }
            #expect(emails.count == 1)
            #expect(emails.first?.recipient.contains(TestHost.ownerAddress) == true)
            host.close()
        }
    }
}
