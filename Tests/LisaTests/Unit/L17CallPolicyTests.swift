// Unit tests for L17, call policy at rule level (CALL-01, REM-02; D-17, D-28): a call needs every condition — enabled,
// the approved destination, a confirmed and still active high-priority commitment, a timed deadline inside the urgency
// window, an outstanding earlier reminder, no quiet hours, daily limits and non-provisional timing — and each unmet
// condition is reported. Defaults keep calls disabled with the R1 limits.

import Foundation
import LisaDomain
import LisaPolicy
import LisaTime
import Testing

@Suite("L17 — Call policy", .tags(.unit))
struct L17CallPolicyTests {
    /// One way to break exactly one call condition, and the reason that must be reported.
    struct BrokenCondition: Sendable, CustomTestStringConvertible {
        var name: String
        var expectedReason: String
        var apply: @Sendable (inout CallContext) throws -> Void

        var testDescription: String { name }
    }

    static let ownerNumber = "+15555550100"
    /// Monday 2026-11-16, 14:00 in New York: outside the default quiet hours.
    static let now = TestTime.instant("2026-11-16T14:00", in: TestTime.newYork)

    /// A context in which every condition holds: the call is allowed.
    static func eligibleContext() -> CallContext {
        CallContext(
            task: SyntheticTask.confirmed(
                priority: .high, deadline: SyntheticTask.due(now.addingTimeInterval(10 * 60)),
                createdAt: now.addingTimeInterval(-86_400)),
            now: now, zone: TestTime.newYork.timeZone,
            settings: CallSettings(enabled: true, approvedNumber: ownerNumber), quietHours: .defaultValue,
            destination: ownerNumber, earlierReminderUnacknowledged: true, callsForCommitmentToday: 0, callsToday: 0,
            basedOnProvisionalPlan: false)
    }

    static let brokenConditions: [BrokenCondition] = [
        BrokenCondition(name: "calls disabled", expectedReason: "calls are not enabled") {
            $0.settings.enabled = false
        },
        BrokenCondition(
            name: "another destination", expectedReason: "the destination is not the approved owner number"
        ) { $0.destination = "+15555550199" },
        BrokenCondition(name: "no destination", expectedReason: "the destination is not the approved owner number") {
            $0.destination = nil
        },
        BrokenCondition(
            name: "no approved number", expectedReason: "the destination is not the approved owner number"
        ) { $0.settings.approvedNumber = nil },
        BrokenCondition(name: "not confirmed", expectedReason: "the commitment is not confirmed") {
            $0.task.confirmation = .possible
        },
        BrokenCondition(name: "completed", expectedReason: "the commitment is already complete or cancelled") {
            try $0.task.transition(to: .completed, at: now)
        },
        BrokenCondition(name: "cancelled", expectedReason: "the commitment is already complete or cancelled") {
            try $0.task.transition(to: .cancelled, at: now)
        },
        BrokenCondition(name: "normal priority", expectedReason: "the commitment is not high priority") {
            $0.task.priority = .normal
        },
        BrokenCondition(name: "deadline too far", expectedReason: "the deadline is not within 15 minutes") {
            $0.task.deadline = SyntheticTask.due(now.addingTimeInterval(15 * 60 + 1))
        },
        BrokenCondition(name: "deadline passed", expectedReason: "the deadline is not within 15 minutes") {
            $0.task.deadline = SyntheticTask.due(now.addingTimeInterval(-60))
        },
        BrokenCondition(name: "date-only deadline", expectedReason: "the commitment has no timed deadline") {
            $0.task.deadline = .onDate(TestTime.date("2026-11-16"))
        },
        BrokenCondition(name: "no deadline", expectedReason: "the commitment has no timed deadline") {
            $0.task.deadline = nil
        },
        BrokenCondition(
            name: "earlier reminder acknowledged",
            expectedReason: "no earlier reminder is outstanding without acknowledgement"
        ) { $0.earlierReminderUnacknowledged = false },
        BrokenCondition(name: "quiet hours", expectedReason: "quiet hours are in effect") {
            let late = TestTime.instant("2026-11-16T22:30", in: TestTime.newYork)
            $0.now = late
            $0.task.deadline = SyntheticTask.due(late.addingTimeInterval(10 * 60))
        },
        BrokenCondition(
            name: "commitment limit", expectedReason: "the daily call limit for this commitment is reached"
        ) { $0.callsForCommitmentToday = 1 },
        BrokenCondition(name: "daily limit", expectedReason: "the daily call limit is reached") { $0.callsToday = 3 },
        BrokenCondition(name: "provisional timing", expectedReason: "the timing is provisional") {
            $0.basedOnProvisionalPlan = true
        },
    ]

    @Test("When every condition holds, the call is allowed")
    func everyConditionHolds() {
        let decision = CallEligibility.evaluate(Self.eligibleContext())
        #expect(decision.allowed)
        #expect(decision.unmetConditions.isEmpty)
    }

    @Test(
        "Breaking any single condition refuses the call and names that condition",
        arguments: L17CallPolicyTests.brokenConditions)
    func eachConditionIsEnforced(_ broken: BrokenCondition) throws {
        var context = Self.eligibleContext()
        try broken.apply(&context)
        let decision = CallEligibility.evaluate(context)
        #expect(!decision.allowed)
        #expect(decision.unmetConditions == [broken.expectedReason])
    }

    @Test("The urgency window is inclusive at 15 minutes and configurable")
    func urgencyWindowBoundary() {
        var context = Self.eligibleContext()
        context.task.deadline = SyntheticTask.due(Self.now.addingTimeInterval(15 * 60))
        #expect(CallEligibility.evaluate(context).allowed)

        context.task.deadline = SyntheticTask.due(Self.now.addingTimeInterval(25 * 60))
        #expect(!CallEligibility.evaluate(context).allowed)
        context.settings.urgencyWindowMinutes = 30
        #expect(CallEligibility.evaluate(context).allowed)
    }

    @Test("An urgent priority counts as high, and the high-priority requirement is configurable")
    func priorityRule() {
        var context = Self.eligibleContext()
        context.task.priority = .urgent
        #expect(CallEligibility.evaluate(context).allowed)
        context.task.priority = .low
        #expect(!CallEligibility.evaluate(context).allowed)
        context.settings.requireHighPriority = false
        #expect(CallEligibility.evaluate(context).allowed)
    }

    @Test("Quiet hours wrap past midnight and end at 07:00 local time")
    func quietHoursWrapMidnight() {
        let quiet = QuietHours.defaultValue
        let zone = TestTime.newYork.timeZone
        for time in ["22:00", "23:59", "00:00", "03:00", "06:59"] {
            #expect(quiet.contains(TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork), in: zone), "\(time)")
        }
        for time in ["07:00", "12:00", "21:59"] {
            #expect(!quiet.contains(TestTime.instant("2026-11-16T\(time)", in: TestTime.newYork), in: zone), "\(time)")
        }
        var context = Self.eligibleContext()
        context.now = TestTime.instant("2026-11-17T06:50", in: TestTime.newYork)
        context.task.deadline = SyntheticTask.due(context.now.addingTimeInterval(5 * 60))
        #expect(CallEligibility.evaluate(context).unmetConditions == ["quiet hours are in effect"])
        context.now = TestTime.instant("2026-11-17T07:00", in: TestTime.newYork)
        context.task.deadline = SyntheticTask.due(context.now.addingTimeInterval(5 * 60))
        #expect(CallEligibility.evaluate(context).allowed)
    }

    @Test("Every unmet condition is listed, not just the first")
    func allUnmetConditionsAreListed() {
        var context = Self.eligibleContext()
        context.settings = CallSettings()
        context.task.confirmation = .possible
        context.earlierReminderUnacknowledged = false
        let decision = CallEligibility.evaluate(context)
        #expect(!decision.allowed)
        #expect(
            decision.unmetConditions == [
                "calls are not enabled", "the destination is not the approved owner number",
                "the commitment is not confirmed", "no earlier reminder is outstanding without acknowledgement",
            ])
    }

    @Test("The defaults keep calls disabled, with one call per commitment and three per day (REM-02)")
    func defaultsAreConservative() {
        let defaults = CallSettings()
        #expect(!defaults.enabled)
        #expect(defaults.approvedNumber == nil)
        #expect(defaults.urgencyWindowMinutes == 15)
        #expect(defaults.requireHighPriority)
        #expect(defaults.requireEarlierUnacknowledgedReminder)
        #expect(defaults.maxCallsPerCommitmentPerDay == 1)
        #expect(defaults.maxCallsPerDay == 3)
        #expect(QuietHours.defaultValue == QuietHours(start: TestTime.time("22:00"), end: TestTime.time("07:00")))

        var context = Self.eligibleContext()
        context.settings.enabled = CallSettings().enabled
        #expect(!CallEligibility.evaluate(context).allowed)
    }
}
