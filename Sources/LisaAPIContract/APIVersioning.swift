// API version, header names, date formats and the JSON coding shared by the host and every client.

import Foundation

/// Versioning and header conventions of the v1 API (API-03).
public enum APIVersioning {
    /// The path prefix of this contract.
    public static let pathPrefix = "/v1"
    /// Sent on every response; clients reject a major version they do not know.
    public static let versionHeader = "Lisa-API-Version"
    public static let version = "1.0"
    /// The stable identity of a mutating request. Retrying with the same ID never repeats the mutation.
    public static let requestIDHeader = "Lisa-Request-ID"
    /// Device credentials use `Authorization: Bearer <credential>`.
    public static let authorizationHeader = "Authorization"
    /// The largest accepted request body.
    public static let maxRequestBytes = 262_144
    /// Idempotency records are kept at least this long: the documented maximum offline retry period.
    public static let idempotencyRetentionDays = 30
}

/// Date formats: instants are ISO 8601 UTC with milliseconds (`2026-11-16T12:00:00.000Z`); local dates are
/// `YYYY-MM-DD`; local times are `HH:MM`.
public enum APIDates {
    public static func string(from date: Date) -> String {
        formatter().string(from: date)
    }

    public static func date(from text: String) -> Date? {
        formatter().date(from: text) ?? fallbackFormatter().date(from: text)
    }

    /// Whether `text` is a valid `YYYY-MM-DD` calendar date.
    public static func isLocalDate(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), (1...12).contains(month)
        else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let days = calendar.range(of: .day, in: .month, for: first)
        else { return false }
        return days.contains(day)
    }

    static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func fallbackFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

/// JSON coding for every DTO.
public enum APIJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIDates.string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = APIDates.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "expected an ISO 8601 instant such as 2026-11-16T12:00:00.000Z")
            }
            return date
        }
        return decoder
    }
}
