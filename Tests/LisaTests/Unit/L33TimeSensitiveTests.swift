// Unit tests for L33, Time Sensitive eligibility at policy level (NOTIFY-06, REM-02, CALL-01; D-17, D-26, D-28): only a
// reminder about an urgent confirmed deadline that meets the configured rule, with the owner's opt-in, uses the Time
// Sensitive level; everything else is standard. The classification never authorizes a call and never bypasses quiet
// hours, recipients or limits; a device can opt out.

import Foundation
import LisaDomain
import LisaPolicy
import LisaTime
import Testing

@Suite("L33 — Time Sensitive eligibility", .tags(.unit))
struct L33TimeSensitiveTests {
    /// One way the urgency rule is not met.
    struct NotUrgent: Sendable, CustomTestStringConvertible {
        var name: String
        var change: @Sendable (inout LisaTask) throws -> Void

        var testDescription: String { name }
    }

    /// Monday 2026-11-16, 14:00 in New York.
    static let now = TestTime.instant("2026-11-16T14:00", in: TestTime.newYork)
    static let optedIn = NotificationSettings(timeSensitiveForUrgentDeadlines: true)

    /// A confirmed, high-priority, open task due in ten minutes.
    static func urgentTask(dueIn minutes: Double = 10) -> LisaTask {
        SyntheticTask.confirmed(
            priority: .high, deadline: SyntheticTask.due(now.addingTimeInterval(minutes * 60)),
            createdAt: now.addingTimeInterval(-86_400))
    }

    static let notUrgentCases: [NotUrgent] = [
        NotUrgent(name: "only possible") { $0.confirmation = .possible },
        NotUrgent(name: "informational") { $0.confirmation = .informational },
        NotUrgent(name: "normal priority") { $0.priority = .normal },
        NotUrgent(name: "low priority") { $0.priority = .low },
        NotUrgent(name: "completed") { try $0.transition(to: .completed, at: now) },
        NotUrgent(name: "cancelled") { try $0.transition(to: .cancelled, at: now) },
        NotUrgent(name: "due in 16 minutes") { $0.deadline = SyntheticTask.due(now.addingTimeInterval(16 * 60)) },
        NotUrgent(name: "deadline passed") { $0.deadline = SyntheticTask.due(now.addingTimeInterval(-60)) },
        NotUrgent(name: "date-only deadline") { $0.deadline = .onDate(TestTime.date("2026-11-16")) },
        NotUrgent(name: "no deadline") { $0.deadline = nil },
    ]

    private func level(
        _ category: NotificationCategory = .reminder, task: LisaTask?,
        settings: NotificationSettings = L33TimeSensitiveTests.optedIn, at instant: Date = L33TimeSensitiveTests.now
    ) -> InterruptionLevel {
        UrgencyRule.interruptionLevel(category: category, task: task, now: instant, settings: settings)
    }

    @Test("A reminder about an urgent confirmed deadline is Time Sensitive when the owner opted in")
    func urgentReminderWithOptIn() {
        #expect(level(task: Self.urgentTask()) == .timeSensitive)
        #expect(UrgencyRule.isUrgentDeadline(Self.urgentTask(), now: Self.now, windowMinutes: 15))
    }

    @Test("Without the owner's opt-in, which is off by default, everything uses the standard level")
    func standardWithoutOptIn() {
        #expect(!NotificationSettings().timeSensitiveForUrgentDeadlines)
        #expect(NotificationSettings().urgentDeadlineWindowMinutes == 15)
        #expect(level(task: Self.urgentTask(), settings: NotificationSettings()) == .active)
    }

    @Test(
        "Every other category uses the standard level, even about an urgent deadline",
        arguments: [NotificationCategory.overdue, .planBlock, .eventProposal, .commitmentChange, .brief])
    func otherCategoriesAreStandard(category: NotificationCategory) {
        #expect(level(category, task: Self.urgentTask()) == .active)
    }

    @Test(
        "A reminder that does not meet the rule uses the standard level",
        arguments: L33TimeSensitiveTests.notUrgentCases)
    func notUrgentIsStandard(_ notUrgent: NotUrgent) throws {
        var task = Self.urgentTask()
        try notUrgent.change(&task)
        #expect(level(task: task) == .active)
        #expect(level(task: nil) == .active)
    }

    @Test("The urgency window includes its end and follows the configured length")
    func windowBoundary() {
        #expect(level(task: Self.urgentTask(dueIn: 15)) == .timeSensitive)
        #expect(level(task: Self.urgentTask(dueIn: 15 + 1.0 / 60)) == .active)
        let wider = NotificationSettings(timeSensitiveForUrgentDeadlines: true, urgentDeadlineWindowMinutes: 30)
        #expect(level(task: Self.urgentTask(dueIn: 25), settings: wider) == .timeSensitive)
        #expect(level(task: Self.urgentTask(dueIn: 31), settings: wider) == .active)
    }

    @Test("A device that opted out receives the notification at the standard level")
    func deviceOptOut() {
        let devices = [
            SyntheticDevice.registration(.iPhone, now: Self.now, id: DeviceID("device-1")),
            SyntheticDevice.registration(
                .iPad, preferences: DeviceNotificationPreferences(allowTimeSensitive: false), now: Self.now,
                id: DeviceID("device-2")),
        ]
        let decisions = NotificationRouting.route(category: .reminder, level: .timeSensitive, devices: devices)
        #expect(decisions.map(\.level) == [.timeSensitive, .active])
        #expect(decisions.map(\.deliver) == [true, true])
    }

    @Test("Time Sensitive never authorizes a call: the call gate still applies every condition")
    func neverAuthorizesCalls() {
        let task = Self.urgentTask()
        #expect(level(task: task) == .timeSensitive)
        func call(_ settings: CallSettings, earlierReminder: Bool, callsToday: Int = 0) -> CallDecision {
            CallEligibility.evaluate(
                CallContext(
                    task: task, now: Self.now, zone: TestTime.newYork.timeZone, settings: settings,
                    quietHours: .defaultValue, destination: "+15555550100",
                    earlierReminderUnacknowledged: earlierReminder,
                    callsForCommitmentToday: 0, callsToday: callsToday, basedOnProvisionalPlan: false))
        }
        #expect(call(CallSettings(), earlierReminder: true).unmetConditions.contains("calls are not enabled"))
        let enabled = CallSettings(enabled: true, approvedNumber: "+15555550100")
        #expect(
            call(enabled, earlierReminder: false).unmetConditions == [
                "no earlier reminder is outstanding without acknowledgement"
            ])
        #expect(
            call(enabled, earlierReminder: true, callsToday: 3).unmetConditions == ["the daily call limit is reached"])
    }

    @Test("Time Sensitive never bypasses quiet hours: an urgent reminder at night waits or expires")
    func neverBypassesQuietHours() {
        let late = TestTime.instant("2026-11-16T23:00", in: TestTime.newYork)
        let task = SyntheticTask.confirmed(
            priority: .urgent, deadline: SyntheticTask.due(late.addingTimeInterval(10 * 60)),
            createdAt: late.addingTimeInterval(-86_400))
        #expect(level(task: task, at: late) == .timeSensitive)
        let zone = TestTime.newYork.timeZone
        let validUntil = DeliveryTiming.validUntil(
            category: .reminder, dueAt: late, deadline: task.deadline, blockEnd: nil, zone: zone,
            settings: Self.optedIn)
        #expect(
            DeliveryTiming.quietHours(at: late, quiet: .defaultValue, zone: zone, validUntil: validUntil) == .expire)
        let lateCall = CallEligibility.evaluate(
            CallContext(
                task: task, now: late, zone: zone,
                settings: CallSettings(enabled: true, approvedNumber: "+15555550100"),
                quietHours: .defaultValue, destination: "+15555550100", earlierReminderUnacknowledged: true,
                callsForCommitmentToday: 0, callsToday: 0, basedOnProvisionalPlan: false))
        #expect(lateCall.unmetConditions == ["quiet hours are in effect"])
    }

    @Test("Time Sensitive never bypasses recipients: disabled, denied and revoked devices are still skipped")
    func neverBypassesRecipients() {
        let enabled = SyntheticDevice.registration(.iPhone, now: Self.now, id: DeviceID("device-1"))
        let disabled = SyntheticDevice.registration(
            .iPad, preferences: DeviceNotificationPreferences(enabled: false), now: Self.now, id: DeviceID("device-2"))
        let denied = SyntheticDevice.registration(
            .iPhone, authorization: .denied, now: Self.now, id: DeviceID("device-3"))
        var revoked = SyntheticDevice.registration(.iPad, now: Self.now, id: DeviceID("device-4"))
        revoked.state = .revoked
        let decisions = NotificationRouting.route(
            category: .reminder, level: .timeSensitive, devices: [enabled, disabled, denied, revoked])
        #expect(decisions.map(\.deviceID) == [enabled.id, disabled.id, denied.id])
        #expect(decisions.map(\.deliver) == [true, false, false])
    }
}
