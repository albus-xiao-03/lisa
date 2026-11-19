// Task, idea and capture DTOs (API-02 task, idea and capture routes).

import Foundation

/// Task states a client may request.
public enum TaskStatusValue: String, Codable, Hashable, Sendable, CaseIterable {
    case open
    case inProgress
    case blocked
    case completed
    case cancelled
}

/// Task priorities.
public enum TaskPriorityValue: String, Codable, Hashable, Sendable, CaseIterable {
    case low
    case normal
    case high
    case urgent
}

/// Whether a task is a confirmed commitment.
public enum ConfirmationValue: String, Codable, Hashable, Sendable, CaseIterable {
    case confirmed
    case possible
    case informational
}

/// A task.
public struct TaskDTO: Codable, Hashable, Sendable {
    public var id: String
    public var revision: Int64
    public var title: String
    public var notes: String
    public var status: TaskStatusValue
    public var priority: TaskPriorityValue
    public var deadline: DeadlineDTO?
    /// A deadline phrase that could not be resolved to a date.
    public var unresolvedDeadlineText: String?
    public var estimatedMinutes: Int?
    public var splittable: Bool
    public var confirmation: ConfirmationValue
    /// `manual`, `extracted` or `capture`.
    public var origin: String
    /// How many evidence records support the task.
    public var evidenceCount: Int
    /// Fields the owner corrected; reprocessing never overwrites them.
    public var ownerCorrected: [String]
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: String, revision: Int64, title: String, notes: String, status: TaskStatusValue, priority: TaskPriorityValue,
        deadline: DeadlineDTO?, unresolvedDeadlineText: String?, estimatedMinutes: Int?, splittable: Bool,
        confirmation: ConfirmationValue, origin: String, evidenceCount: Int, ownerCorrected: [String], createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.revision = revision
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.unresolvedDeadlineText = unresolvedDeadlineText
        self.estimatedMinutes = estimatedMinutes
        self.splittable = splittable
        self.confirmation = confirmation
        self.origin = origin
        self.evidenceCount = evidenceCount
        self.ownerCorrected = ownerCorrected
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

/// `POST /v1/tasks`: a confirmed manual task.
public struct TaskCreateRequest: Codable, Hashable, Sendable {
    public var title: String
    public var notes: String?
    public var priority: TaskPriorityValue?
    public var deadline: DeadlineDTO?
    public var estimatedMinutes: Int?
    public var splittable: Bool?

    public init(
        title: String, notes: String? = nil, priority: TaskPriorityValue? = nil, deadline: DeadlineDTO? = nil,
        estimatedMinutes: Int? = nil, splittable: Bool? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.deadline = deadline
        self.estimatedMinutes = estimatedMinutes
        self.splittable = splittable
    }
}

/// `PATCH /v1/tasks/{id}`. Omitted fields are unchanged; `clearDeadline` removes the deadline.
public struct TaskPatchRequest: Codable, Hashable, Sendable {
    /// The revision the client last saw; a mismatch is a conflict.
    public var expectedRevision: Int64
    public var status: TaskStatusValue?
    public var title: String?
    public var notes: String?
    public var priority: TaskPriorityValue?
    public var deadline: DeadlineDTO?
    public var clearDeadline: Bool?
    public var estimatedMinutes: Int?
    public var confirmation: ConfirmationValue?

    public init(
        expectedRevision: Int64, status: TaskStatusValue? = nil, title: String? = nil, notes: String? = nil,
        priority: TaskPriorityValue? = nil, deadline: DeadlineDTO? = nil, clearDeadline: Bool? = nil,
        estimatedMinutes: Int? = nil, confirmation: ConfirmationValue? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.status = status
        self.title = title
        self.notes = notes
        self.priority = priority
        self.deadline = deadline
        self.clearDeadline = clearDeadline
        self.estimatedMinutes = estimatedMinutes
        self.confirmation = confirmation
    }
}

/// Idea lifecycle states.
public enum IdeaLifecycleValue: String, Codable, Hashable, Sendable, CaseIterable {
    case inbox
    case availableForPlanning
    case scheduled
    case explored
    case archived
}

/// An idea. `originalCapture` is the owner's words exactly as captured.
public struct IdeaDTO: Codable, Hashable, Sendable {
    public var id: String
    public var revision: Int64
    public var originalCapture: String
    public var summary: String
    public var tags: [String]
    public var notes: String
    public var priority: TaskPriorityValue
    public var estimatedMinutes: Int?
    public var deadline: DeadlineDTO?
    public var lifecycle: IdeaLifecycleValue
    /// Why the idea could not be scheduled recently, if it could not.
    public var unschedulableReason: String?
    public var unschedulableCount: Int
    public var createdAt: Date

    public init(
        id: String, revision: Int64, originalCapture: String, summary: String, tags: [String], notes: String,
        priority: TaskPriorityValue, estimatedMinutes: Int?, deadline: DeadlineDTO?, lifecycle: IdeaLifecycleValue,
        unschedulableReason: String?, unschedulableCount: Int, createdAt: Date
    ) {
        self.id = id
        self.revision = revision
        self.originalCapture = originalCapture
        self.summary = summary
        self.tags = tags
        self.notes = notes
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.lifecycle = lifecycle
        self.unschedulableReason = unschedulableReason
        self.unschedulableCount = unschedulableCount
        self.createdAt = createdAt
    }
}

/// `PATCH /v1/ideas/{id}`. Omitted fields are unchanged.
public struct IdeaPatchRequest: Codable, Hashable, Sendable {
    public var expectedRevision: Int64
    public var lifecycle: IdeaLifecycleValue?
    public var summary: String?
    public var tags: [String]?
    public var notes: String?
    public var priority: TaskPriorityValue?
    public var estimatedMinutes: Int?
    public var deadline: DeadlineDTO?
    public var clearDeadline: Bool?

    public init(
        expectedRevision: Int64, lifecycle: IdeaLifecycleValue? = nil, summary: String? = nil, tags: [String]? = nil,
        notes: String? = nil, priority: TaskPriorityValue? = nil, estimatedMinutes: Int? = nil,
        deadline: DeadlineDTO? = nil, clearDeadline: Bool? = nil
    ) {
        self.expectedRevision = expectedRevision
        self.lifecycle = lifecycle
        self.summary = summary
        self.tags = tags
        self.notes = notes
        self.priority = priority
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.clearDeadline = clearDeadline
    }
}

/// What is being captured.
public enum CaptureKindValue: String, Codable, Hashable, Sendable, CaseIterable {
    case idea
    case text
    case link
    case sharedAppleNews
}

/// Where a capture came from.
public enum CaptureChannelValue: String, Codable, Hashable, Sendable, CaseIterable {
    case commandLine
    case api
    case nativeApp
    case siri
    case demonstration
}

/// `POST /v1/captures`. The request ID header makes retries return the original capture.
public struct CaptureRequestDTO: Codable, Hashable, Sendable {
    public var kind: CaptureKindValue
    public var text: String?
    public var url: String?
    public var title: String?
    public var channel: CaptureChannelValue

    public init(
        kind: CaptureKindValue, text: String? = nil, url: String? = nil, title: String? = nil,
        channel: CaptureChannelValue
    ) {
        self.kind = kind
        self.text = text
        self.url = url
        self.title = title
        self.channel = channel
    }
}

/// A saved capture and what it produced.
public struct CaptureDTO: Codable, Hashable, Sendable {
    public var id: String
    public var kind: CaptureKindValue
    public var capturedAt: Date
    /// `saved`, `processed`, `awaitingModel` or `failed`.
    public var processing: String
    public var ideaID: String?
    public var newsID: String?
    /// False when the request ID matched an earlier capture.
    public var created: Bool

    public init(
        id: String, kind: CaptureKindValue, capturedAt: Date, processing: String, ideaID: String?, newsID: String?,
        created: Bool
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.processing = processing
        self.ideaID = ideaID
        self.newsID = newsID
        self.created = created
    }
}

/// `POST /v1/captures/{id}/retrieve`: what reading the page behind a captured link did (NEWS-01).
///
/// A page is read once. When `retrieved` is false the page could not be read for a lasting reason (it needs signing in
/// or payment, is not a web page, is too large, or its address is refused): `failureClass` and `failureSummary` say
/// why, the item is unchanged and nothing from the page was kept. Text read from a page is labeled `pageText`: what the
/// site serves an anonymous reader, which for a paywalled page can be only its public part.
public struct CaptureRetrievalDTO: Codable, Hashable, Sendable {
    public var captureID: String
    public var newsID: String
    /// Whether the page was read and kept.
    public var retrieved: Bool
    /// The item's accessible-content boundary afterwards: `pageText` when the page's text was read; otherwise as
    /// before, usually `titleOnly` (also when a page that was read has no text Lisa can read without scripts).
    public var boundary: String
    /// The item's title: the page's own title when the item had only the link as its title.
    public var title: String
    /// The address that served the page, after redirects, when it was read.
    public var pageURL: String?
    /// When the page was read.
    public var retrievedAt: Date?
    /// How many characters of the page's text the item keeps.
    public var textCharacters: Int
    /// Whether the page's text was cut at a size bound, so the item keeps only its beginning.
    public var textTruncated: Bool
    /// Why the page was not read, as a source error class: `authentication`, `permissionDenied`, `unsupported`,
    /// `configuration` or `parse`.
    public var failureClass: String?
    /// The reason in words, without the address's path or query.
    public var failureSummary: String?

    public init(
        captureID: String, newsID: String, retrieved: Bool, boundary: String, title: String, pageURL: String?,
        retrievedAt: Date?, textCharacters: Int, textTruncated: Bool, failureClass: String?, failureSummary: String?
    ) {
        self.captureID = captureID
        self.newsID = newsID
        self.retrieved = retrieved
        self.boundary = boundary
        self.title = title
        self.pageURL = pageURL
        self.retrievedAt = retrievedAt
        self.textCharacters = textCharacters
        self.textTruncated = textTruncated
        self.failureClass = failureClass
        self.failureSummary = failureSummary
    }
}
