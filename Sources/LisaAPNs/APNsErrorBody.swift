// Defensive parsing of an APNs error response body: the `reason` string and the 410 `timestamp`, which Apple
// documents in milliseconds since 1970 (S13).

import Foundation
import LisaTime

/// The JSON object APNs sends with an error status. Anything malformed or oversized parses as an empty body; nothing
/// here can fail or grow without bound.
public struct APNsErrorBody: Hashable, Sendable {
    /// The largest body parsed, which is also the response limit of APNs requests.
    public static let maxBytes = 16_384
    /// The longest undocumented reason kept.
    public static let maxUnrecognizedReasonLength = 64
    /// 9999-12-31T23:59:59.999Z in milliseconds: the latest timestamp accepted.
    static let latestMilliseconds: Int64 = 253_402_300_799_999

    /// A documented reason.
    public var reason: APNsReason?
    /// An undocumented reason as sent, reduced to ASCII letters and digits and at most 64 characters.
    public var unrecognizedReason: String?
    /// When APNs confirmed the token was no longer valid for the topic (410 only), from milliseconds since 1970.
    public var timestamp: Date?

    public init(reason: APNsReason? = nil, unrecognizedReason: String? = nil, timestamp: Date? = nil) {
        self.reason = reason
        self.unrecognizedReason = unrecognizedReason
        self.timestamp = timestamp
    }

    /// Parses `body`. A timestamp is accepted as a JSON integer, a JSON number, or a string of digits.
    public init(parsing body: Data) {
        self.init()
        guard !body.isEmpty, body.count <= Self.maxBytes,
            let wire = try? JSONDecoder().decode(ErrorBodyWire.self, from: body)
        else { return }
        if let text = wire.reason {
            if let known = APNsReason(rawValue: text) {
                reason = known
            } else {
                var kept = String.UnicodeScalarView()
                for scalar in text.unicodeScalars where kept.count < Self.maxUnrecognizedReasonLength {
                    let value = scalar.value
                    if (0x30...0x39).contains(value) || (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
                        kept.append(scalar)
                    }
                }
                unrecognizedReason = kept.isEmpty ? nil : String(kept)
            }
        }
        if let milliseconds = wire.timestamp, milliseconds > 0, milliseconds <= Self.latestMilliseconds {
            timestamp = Date(millisecondsSince1970: milliseconds)
        }
    }

    /// The reason as shown in results: the documented string, the reduced undocumented one, or "no reason given".
    public var label: String {
        if let reason { return reason.rawValue }
        if let unrecognizedReason { return "unrecognized reason \(unrecognizedReason)" }
        return "no reason given"
    }
}

/// The wire form, decoded leniently: a field of an unexpected type is treated as absent.
private struct ErrorBodyWire: Decodable {
    var reason: String?
    var timestamp: Int64?

    private enum CodingKeys: String, CodingKey {
        case reason
        case timestamp
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        if let integer = try? container.decodeIfPresent(Int64.self, forKey: .timestamp) {
            timestamp = integer
        } else if let number = try? container.decodeIfPresent(Double.self, forKey: .timestamp), number.isFinite,
            number >= 1, number <= Double(APNsErrorBody.latestMilliseconds)
        {
            timestamp = Int64(number)
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .timestamp),
            (1...18).contains(text.utf8.count), text.utf8.allSatisfy({ (0x30...0x39).contains($0) })
        {
            timestamp = Int64(text)
        } else {
            timestamp = nil
        }
    }
}
