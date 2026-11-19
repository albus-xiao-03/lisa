// Delivery timing: quiet-hour deferral, validity windows and bounded exponential backoff with jitter.

import Foundation
import LisaDomain
import LisaTime

/// What to do with a delivery that would fall into quiet hours.
public enum QuietHoursDecision: Hashable, Sendable {
    case sendNow
    case deferUntil(Date)
    case expire
}

/// Timing rules shared by every channel.
public enum DeliveryTiming {
    /// Defers to the end of quiet hours when the delivery is still valid then; otherwise it expires.
    public static func quietHours(at now: Date, quiet: QuietHours, zone: TimeZone, validUntil: Date?)
        -> QuietHoursDecision
    {
        guard quiet.contains(now, in: zone) else { return .sendNow }
        let allowed = quiet.nextAllowedInstant(after: now, in: zone)
        if let validUntil, allowed >= validUntil { return .expire }
        return .deferUntil(allowed)
    }

    /// The delay before retry `attempt` (1-based): exponential from `baseSeconds`, capped, with jitter in [0.5, 1.0].
    /// `random` supplies a value in [0, 1) so the schedule is reproducible under test.
    public static func backoff(attempt: Int, baseSeconds: Int, maxSeconds: Int, random: Double) -> TimeInterval {
        let exponent = min(max(0, attempt - 1), 20)
        let raw = min(Double(maxSeconds), Double(baseSeconds) * pow(2, Double(exponent)))
        return raw * (0.5 + 0.5 * min(max(random, 0), 1))
    }

    /// How long a notification stays deliverable (NOTIFY-03 expiry).
    public static func validUntil(
        category: NotificationCategory, dueAt: Date, deadline: Deadline?, blockEnd: Date?, zone: TimeZone,
        settings: NotificationSettings
    ) -> Date {
        let fallback = dueAt.addingTimeInterval(TimeInterval(settings.defaultValidityMinutes * 60))
        let endOfDay = ZoneRules.startOfDay(ZoneRules.localDate(for: dueAt, in: zone).adding(days: 1), in: zone)
        switch category {
        case .reminder:
            if let deadline { return max(dueAt, min(fallback, deadline.latestInstant(in: zone))) }
            return fallback
        case .planBlock:
            return blockEnd ?? fallback
        case .overdue, .eventProposal, .brief:
            return endOfDay
        case .commitmentChange:
            return fallback
        }
    }
}
