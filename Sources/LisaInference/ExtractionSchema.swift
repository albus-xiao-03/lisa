// The structured-output schema the model must return, and the validated form Lisa uses (MODEL-02).

import Foundation
import LisaDomain
import LisaTime

/// The raw JSON shape requested from a model.
public struct ModelExtractionPayload: Codable, Sendable {
    public var items: [ModelExtractedItem]

    public init(items: [ModelExtractedItem]) {
        self.items = items
    }
}

/// One raw item. Every field is checked by ``ExtractionValidator`` before use.
public struct ModelExtractedItem: Codable, Hashable, Sendable {
    public var kind: String
    public var title: String
    public var confirmation: String
    public var deadline: String?
    public var start: String?
    public var end: String?
    public var durationMinutes: Int?
    public var location: String?
    public var participants: [String]?
    public var priority: String?
    /// An exact quote from the source that supports the item.
    public var evidence: String
    public var addressedToOwner: Bool?
    public var confidence: String?

    public init(
        kind: String, title: String, confirmation: String, deadline: String? = nil, start: String? = nil,
        end: String? = nil, durationMinutes: Int? = nil, location: String? = nil, participants: [String]? = nil,
        priority: String? = nil, evidence: String, addressedToOwner: Bool? = nil, confidence: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.confirmation = confirmation
        self.deadline = deadline
        self.start = start
        self.end = end
        self.durationMinutes = durationMinutes
        self.location = location
        self.participants = participants
        self.priority = priority
        self.evidence = evidence
        self.addressedToOwner = addressedToOwner
        self.confidence = confidence
    }

    /// The schema description included in prompts.
    public static let schemaDescription = """
        Return JSON: {"items": [{"kind": "commitment|meeting|request|change|information", "title": string,
        "confirmation": "confirmed|possible|informational", "deadline": string?, "start": string?, "end": string?,
        "durationMinutes": integer?, "location": string?, "participants": [string]?, "priority": "low|normal|high|urgent"?,
        "evidence": exact quote from the content, "addressedToOwner": boolean?, "confidence": "low|medium|high"?}]}.
        Write dates exactly as they appear; never invent a date or time. Use "possible" unless the content states
        a commitment was confirmed.
        """
}

/// What an extracted item is.
public enum ExtractedKind: String, Codable, Sendable, CaseIterable {
    case commitment
    case meeting
    case request
    case change
    case information
}

/// A confidence label. It is a label, not a calibrated probability (MODEL-02).
public enum ConfidenceLabel: String, Codable, Sendable {
    case low
    case medium
    case high
}

/// A resolved date phrase.
public enum ResolvedWhen: Hashable, Sendable {
    case instant(Date)
    case date(LocalDate)
    case unresolved(text: String, candidates: [LocalDate])
}

/// An item that passed validation.
public struct ValidatedItem: Hashable, Sendable {
    public var kind: ExtractedKind
    public var title: String
    public var confirmation: Confirmation
    public var deadline: ResolvedWhen?
    public var start: ResolvedWhen?
    public var end: ResolvedWhen?
    public var durationMinutes: Int?
    public var location: String?
    public var participants: [String]
    public var priority: TaskPriority
    public var evidenceQuote: String
    public var addressedToOwner: Bool
    public var confidence: ConfidenceLabel?
    /// Adjustments the validator made, such as downgrading an unsupported "confirmed".
    public var notes: [String]
}

/// The validated result of one extraction.
public struct ValidatedExtraction: Hashable, Sendable {
    public var items: [ValidatedItem]
    /// Items that were rejected, with the reason.
    public var rejected: [String]
    public var provider: ModelDescriptor
    public var repairAttempted: Bool
}
