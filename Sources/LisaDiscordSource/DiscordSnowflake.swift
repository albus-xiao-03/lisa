// Discord snowflake identifiers: decimal strings of 64-bit numbers, compared numerically and dated by their timestamp.

import Foundation

/// Snowflake IDs "are up to 64 bits in size (e.g. a uint64)" and "always returned as strings in the HTTP API"; the top
/// 42 bits are milliseconds since the Discord epoch, `(snowflake >> 22) + 1420070400000`
/// (https://docs.discord.com/developers/reference.md#snowflakes).
enum DiscordSnowflake {
    /// The Discord epoch, the first second of 2015, in milliseconds since 1970.
    static let epochMilliseconds: UInt64 = 1_420_070_400_000

    /// The numeric value of a decimal snowflake of 1 to 20 digits, or nil.
    static func value(_ text: String) -> UInt64? {
        guard (1...20).contains(text.utf8.count), text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return UInt64(text)
    }

    static func isValid(_ text: String) -> Bool {
        value(text) != nil
    }

    /// When the snowflake was created.
    static func date(of value: UInt64) -> Date {
        let milliseconds = (value >> 22) + epochMilliseconds
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }
}
