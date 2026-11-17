// Whole seconds since 1970 for APNs header and token fields, clamped so that no date can overflow the conversion.

import Foundation

/// Converts instants to the integer seconds APNs expects in `apns-expiration` and in the token's `iat`.
enum APNsEpochSeconds {
    /// 9999-12-31T23:59:59Z, the latest value produced.
    static let latest: Int64 = 253_402_300_799

    /// The whole seconds of `date` since 1970, rounded down; 0 for instants before 1970, ``latest`` after it.
    static func of(_ date: Date) -> Int64 {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return seconds >= Double(latest) ? latest : Int64(seconds)
    }
}
