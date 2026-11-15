// Offset rules for any zone description (IANA zones or embedded calendar zones), with gap and overlap resolution.

import Foundation

/// Anything that knows a zone's offset from UTC at a given instant: an IANA `TimeZone` or a calendar's VTIMEZONE.
public protocol UTCOffsetRules: Sendable {
    /// Seconds east of UTC in force at `instant`.
    func secondsFromUTC(at instant: Date) -> Int
}

extension TimeZone: UTCOffsetRules {
    public func secondsFromUTC(at instant: Date) -> Int {
        secondsFromGMT(for: instant)
    }
}

/// A zone with one fixed offset, for example a UTC offset written in a calendar file.
public struct FixedOffsetRules: UTCOffsetRules {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    public func secondsFromUTC(at instant: Date) -> Int { seconds }
}

extension ZoneRules {
    /// Resolves `local` under arbitrary offset rules, reporting gaps and overlaps explicitly (RFC 5545 semantics).
    public static func resolve(_ local: LocalDateTime, rules: some UTCOffsetRules) -> LocalTimeResolution {
        let naive = TimeInterval(local.secondsSinceEpoch)
        let offsetBefore = rules.secondsFromUTC(at: Date(timeIntervalSince1970: naive - 86_400))
        let offsetAfter = rules.secondsFromUTC(at: Date(timeIntervalSince1970: naive + 86_400))
        var valid: [Date] = []
        for offset in Set([offsetBefore, offsetAfter]) {
            let candidate = Date(timeIntervalSince1970: naive - TimeInterval(offset))
            if rules.secondsFromUTC(at: candidate) == offset {
                valid.append(candidate)
            }
        }
        valid.sort()
        if valid.count >= 2, let earlier = valid.first, let later = valid.last, earlier != later {
            return .overlap(earlier: earlier, later: later)
        }
        if let only = valid.first {
            return .exact(only)
        }
        let shifted = Date(timeIntervalSince1970: naive - TimeInterval(offsetBefore))
        return .gap(shifted: shifted, gapSeconds: offsetAfter - offsetBefore)
    }

    /// The instant for `local` under `rules`: the earlier instant in an overlap, the shifted instant in a gap.
    public static func instant(for local: LocalDateTime, rules: some UTCOffsetRules) -> Date {
        switch resolve(local, rules: rules) {
        case .exact(let date): date
        case .gap(let shifted, _): shifted
        case .overlap(let earlier, _): earlier
        }
    }

    /// The local date-time of `instant` under `rules`.
    public static func local(for instant: Date, rules: some UTCOffsetRules) -> LocalDateTime {
        let offset = rules.secondsFromUTC(at: instant)
        return LocalDateTime(secondsSinceEpoch: Int(instant.timeIntervalSince1970.rounded(.down)) + offset)
    }
}
