// CALL-01: every condition for an outbound call, enforced by deterministic code and reported condition by condition.

import Foundation
import LisaDomain

/// The facts a call decision is based on.
public struct CallContext: Sendable {
    public var task: LisaTask
    public var now: Date
    public var zone: TimeZone
    public var settings: CallSettings
    public var quietHours: QuietHours
    /// The intended destination; it must equal the approved owner number.
    public var destination: String?
    /// An earlier reminder for this commitment reached a provider or was presented locally, and the owner has not
    /// acknowledged it. A missing push acknowledgement satisfies only this condition, never the others.
    public var earlierReminderUnacknowledged: Bool
    public var callsForCommitmentToday: Int
    public var callsToday: Int
    /// True when the commitment's time comes from a provisional plan; provisional suggestions never escalate.
    public var basedOnProvisionalPlan: Bool

    public init(
        task: LisaTask, now: Date, zone: TimeZone, settings: CallSettings, quietHours: QuietHours, destination: String?,
        earlierReminderUnacknowledged: Bool, callsForCommitmentToday: Int, callsToday: Int, basedOnProvisionalPlan: Bool
    ) {
        self.task = task
        self.now = now
        self.zone = zone
        self.settings = settings
        self.quietHours = quietHours
        self.destination = destination
        self.earlierReminderUnacknowledged = earlierReminderUnacknowledged
        self.callsForCommitmentToday = callsForCommitmentToday
        self.callsToday = callsToday
        self.basedOnProvisionalPlan = basedOnProvisionalPlan
    }
}

/// The decision and the conditions that were not met.
public struct CallDecision: Hashable, Sendable {
    public var allowed: Bool
    public var unmetConditions: [String]
}

/// Evaluates call escalation.
public enum CallEligibility {
    public static func evaluate(_ context: CallContext) -> CallDecision {
        var unmet: [String] = []
        let settings = context.settings
        if !settings.enabled { unmet.append("calls are not enabled") }
        if settings.approvedNumber == nil || context.destination == nil
            || context.destination != settings.approvedNumber
        {
            unmet.append("the destination is not the approved owner number")
        }
        if !context.task.isConfirmedCommitment { unmet.append("the commitment is not confirmed") }
        if !context.task.status.isActive { unmet.append("the commitment is already complete or cancelled") }
        if settings.requireHighPriority, !context.task.priority.isHigh {
            unmet.append("the commitment is not high priority")
        }
        if case .at(let instant, _) = context.task.deadline {
            let remaining = instant.timeIntervalSince(context.now)
            if remaining <= 0 || remaining > TimeInterval(settings.urgencyWindowMinutes * 60) {
                unmet.append("the deadline is not within \(settings.urgencyWindowMinutes) minutes")
            }
        } else {
            unmet.append("the commitment has no timed deadline")
        }
        if settings.requireEarlierUnacknowledgedReminder, !context.earlierReminderUnacknowledged {
            unmet.append("no earlier reminder is outstanding without acknowledgement")
        }
        if context.quietHours.contains(context.now, in: context.zone) { unmet.append("quiet hours are in effect") }
        if context.callsForCommitmentToday >= settings.maxCallsPerCommitmentPerDay {
            unmet.append("the daily call limit for this commitment is reached")
        }
        if context.callsToday >= settings.maxCallsPerDay { unmet.append("the daily call limit is reached") }
        if context.basedOnProvisionalPlan { unmet.append("the timing is provisional") }
        return CallDecision(allowed: unmet.isEmpty, unmetConditions: unmet)
    }
}
