// Run IDs (plan §10.8 "Unique IDs"; docs/DECISIONS.md D-54): `run-YYYYMMDDTHHMMSSZ-<6 lowercase base32 characters>`.

import Foundation

/// A run's identifier: its UTC start time and six random RFC 4648 base32 characters in lowercase. It is a safe path
/// component and sorts by start time.
public struct VerifyRunID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let text: String

    public var description: String { text }

    /// Accepts only the exact spelling.
    public init(_ text: String) throws(VerifyError) {
        guard Self.isValid(text) else { throw .invalidRunID(text) }
        self.text = text
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard Self.isValid(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "run ID"))
        }
        self.text = text
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    public static func < (lhs: VerifyRunID, rhs: VerifyRunID) -> Bool { lhs.text < rhs.text }

    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    /// A new run ID for `date`, with six random characters.
    public static func generate(at date: Date = Date()) -> VerifyRunID {
        var generator = SystemRandomNumberGenerator()
        return generate(at: date, using: &generator)
    }

    /// A new run ID for `date`, drawing its six characters from `generator`.
    public static func generate(at date: Date, using generator: inout some RandomNumberGenerator) -> VerifyRunID {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let time =
            pad(c.year ?? 0, 4) + pad(c.month ?? 0, 2) + pad(c.day ?? 0, 2) + "T" + pad(c.hour ?? 0, 2)
            + pad(c.minute ?? 0, 2) + pad(c.second ?? 0, 2) + "Z"
        let suffix = String((0..<6).map { _ in alphabet[Int.random(in: 0..<32, using: &generator)] })
        // The spelling is built to be valid.
        return try! VerifyRunID("run-" + time + "-" + suffix)
    }

    /// Whether `text` is `run-YYYYMMDDTHHMMSSZ-xxxxxx` with a real UTC date and time and lowercase base32.
    public static func isValid(_ text: String) -> Bool {
        let chars = Array(text.utf8)
        guard chars.count == 27, text.hasPrefix("run-"), chars[20] == UInt8(ascii: "-"),
            chars[12] == UInt8(ascii: "T"), chars[19] == UInt8(ascii: "Z")
        else { return false }
        let digits = Array(chars[4..<12]) + Array(chars[13..<19])
        guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return false }
        func number(_ range: Range<Int>) -> Int { Int(String(decoding: chars[range], as: UTF8.self)) ?? -1 }
        let (year, month, day) = (number(4..<8), number(8..<10), number(10..<12))
        let (hour, minute, second) = (number(13..<15), number(15..<17), number(17..<19))
        guard year >= 2000, (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
            (0...59).contains(minute), (0...59).contains(second)
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month
        else { return false }
        let alphabetBytes = Set(alphabet.map { $0.asciiValue! })
        return chars[21..<27].allSatisfy { alphabetBytes.contains($0) }
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
