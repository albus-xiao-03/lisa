// Validates model output: types, enums, evidence quotes, dates, bounds, confirmation authority and addressing.

import Foundation
import LisaDomain
import LisaTime

/// Context that decides what the content can and cannot establish.
public struct ExtractionContext: Hashable, Sendable {
    /// The text that was sent to the model; evidence quotes must occur in it.
    public var sourceText: String
    /// The part written by the owner (for example the note above a forwarded message). Only quotes from it can
    /// make an item "confirmed".
    public var ownerAuthoredText: String?
    public var addressing: OwnerAddressing
    /// The source timestamp that relative dates are resolved against.
    public var referenceInstant: Date
    public var zone: TimeZone
    public var dateReading: DateReadingSettings

    public init(
        sourceText: String, ownerAuthoredText: String?, addressing: OwnerAddressing, referenceInstant: Date,
        zone: TimeZone, dateReading: DateReadingSettings
    ) {
        self.sourceText = sourceText
        self.ownerAuthoredText = ownerAuthoredText
        self.addressing = addressing
        self.referenceInstant = referenceInstant
        self.zone = zone
        self.dateReading = dateReading
    }
}

/// Why a whole payload was unusable (eligible for one bounded repair attempt).
public enum PayloadError: Error, Hashable, Sendable, CustomStringConvertible {
    case tooLarge
    case notJSON(String)
    case tooManyItems(Int)

    public var description: String {
        switch self {
        case .tooLarge: "the response exceeds the size limit"
        case .notJSON(let reason): "the response is not valid JSON in the required shape (\(reason))"
        case .tooManyItems(let count): "the response has \(count) items, more than allowed"
        }
    }
}

/// Validation of structured model output (MODEL-02).
public enum ExtractionValidator {
    /// Decodes the payload, accepting a JSON object optionally wrapped in a Markdown code fence.
    public static func decode(_ text: String, limits: ModelUsageLimits) throws -> ModelExtractionPayload {
        guard text.utf8.count <= limits.maxResponseBytes else { throw PayloadError.tooLarge }
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if let fence = body.range(of: "```", options: .backwards) { body = String(body[..<fence.lowerBound]) }
        }
        do {
            let payload = try JSONDecoder().decode(ModelExtractionPayload.self, from: Data(body.utf8))
            guard payload.items.count <= limits.maxItems else { throw PayloadError.tooManyItems(payload.items.count) }
            return payload
        } catch let error as PayloadError {
            throw error
        } catch {
            throw PayloadError.notJSON(String(describing: error).prefix(200).description)
        }
    }

    /// Validates each item; invalid items are rejected with a reason, never repaired by guessing.
    public static func validate(_ payload: ModelExtractionPayload, context: ExtractionContext) -> (
        items: [ValidatedItem], rejected: [String]
    ) {
        var items: [ValidatedItem] = []
        var rejected: [String] = []
        let normalizedSource = normalize(context.sourceText)
        let normalizedOwner = context.ownerAuthoredText.map(normalize)
        for (index, raw) in payload.items.enumerated() {
            let label = "item \(index + 1)"
            guard let kind = ExtractedKind(rawValue: raw.kind.lowercased()) else {
                rejected.append("\(label): unknown kind \"\(raw.kind.prefix(40))\"")
                continue
            }
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 200 else {
                rejected.append("\(label): missing or oversized title")
                continue
            }
            let quote = normalize(raw.evidence)
            guard !quote.isEmpty, raw.evidence.count <= 500, normalizedSource.contains(quote) else {
                rejected.append("\(label): the evidence quote does not appear in the source")
                continue
            }
            guard var confirmation = Confirmation(rawValue: raw.confirmation.lowercased()) else {
                rejected.append("\(label): unknown confirmation \"\(raw.confirmation.prefix(40))\"")
                continue
            }
            var notes: [String] = []
            if confirmation == .confirmed, !(normalizedOwner?.contains(quote) ?? false) {
                confirmation = .possible
                notes.append("confirmation downgraded: the quote is not the owner's own words")
            }
            var addressed = raw.addressedToOwner ?? true
            if context.addressing == .carbonCopy || context.addressing == .unknownSender {
                addressed = false
                if confirmation == .confirmed {
                    confirmation = .possible
                    notes.append("the owner was not the addressee")
                }
            }
            let deadline = raw.deadline.flatMap { resolve($0, context: context) }
            let start = raw.start.flatMap { resolve($0, context: context) }
            let end = raw.end.flatMap { resolve($0, context: context) }
            if let deadline, !withinBounds(deadline, context: context) {
                rejected.append("\(label): the deadline is outside the plausible range")
                continue
            }
            if let start, !withinBounds(start, context: context) {
                rejected.append("\(label): the start is outside the plausible range")
                continue
            }
            let duration = raw.durationMinutes.flatMap { (1...1440).contains($0) ? $0 : nil }
            if raw.durationMinutes != nil, duration == nil { notes.append("an out-of-range duration was ignored") }
            items.append(
                ValidatedItem(
                    kind: kind, title: title, confirmation: confirmation, deadline: deadline, start: start, end: end,
                    durationMinutes: duration, location: raw.location.map { String($0.prefix(200)) },
                    participants: (raw.participants ?? []).prefix(20).map { String($0.prefix(100)) },
                    priority: raw.priority.flatMap { TaskPriority(rawValue: $0.lowercased()) } ?? .normal,
                    evidenceQuote: raw.evidence, addressedToOwner: addressed,
                    confidence: raw.confidence.flatMap { ConfidenceLabel(rawValue: $0.lowercased()) }, notes: notes))
        }
        return (items, rejected)
    }

    /// Resolves a written date phrase such as "Friday at 3pm" or "2026-11-20 10:00" against the reference.
    static func resolve(_ phrase: String, context: ExtractionContext) -> ResolvedWhen? {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 120 else { return nil }
        if let instant = InternetDateParser.parseISO8601(text), text.contains("T") || text.contains(":") {
            return .instant(instant)
        }
        let timePattern = #"(\b\d{1,2}(:\d{2})?\s?(am|pm|a\.m\.|p\.m\.)\b|\b\d{1,2}:\d{2}\b|\bnoon\b|\bmidnight\b)"#
        var datePart = text
        var time: LocalTime?
        if let range = text.range(of: timePattern, options: [.regularExpression, .caseInsensitive]) {
            time = TimeOfDayParser.parse(String(text[range]))
            datePart = text.replacingCharacters(in: range, with: " ")
                .replacingOccurrences(
                    of: #"\b(at|by|before)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]
                )
                .trimmingCharacters(in: .whitespaces)
        }
        let resolver = RelativeDateResolver(
            reference: context.referenceInstant, zone: context.zone, settings: context.dateReading)
        let resolution = datePart.isEmpty ? .resolved(resolver.referenceDate) : resolver.resolve(datePart)
        switch resolution {
        case .resolved(let date):
            guard let time else { return .date(date) }
            return .instant(ZoneRules.instant(for: LocalDateTime(date: date, time: time), in: context.zone))
        case .ambiguous(let candidates, _):
            return .unresolved(text: text, candidates: candidates)
        case .unrecognized:
            return .unresolved(text: text, candidates: [])
        }
    }

    static func withinBounds(_ value: ResolvedWhen, context: ExtractionContext) -> Bool {
        let lower = context.referenceInstant.addingTimeInterval(-366 * 86_400)
        let upper = context.referenceInstant.addingTimeInterval(5 * 366 * 86_400)
        switch value {
        case .instant(let instant): return instant >= lower && instant <= upper
        case .date(let date):
            let instant = ZoneRules.startOfDay(date, in: context.zone)
            return instant >= lower && instant <= upper
        case .unresolved: return true
        }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
