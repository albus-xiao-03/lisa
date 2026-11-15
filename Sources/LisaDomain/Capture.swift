// A raw capture (idea, text, link or shared Apple News item), saved immediately and independently of any model.

import Foundation

/// What was captured.
public enum CaptureKind: String, Codable, Sendable {
    case idea
    case text
    case link
    case sharedAppleNews
}

/// Where a capture came from.
public enum CaptureChannel: String, Codable, Sendable {
    case commandLine
    case api
    case nativeApp
    case siri
    case demonstration
    case localImport
}

/// Processing progress after the raw input has been saved.
public enum CaptureProcessing: String, Codable, Sendable {
    case saved
    case processed
    case awaitingModel
    case failed
}

/// The original input exactly as supplied. Saved before any interpretation (IDEA-01).
public struct Capture: Entity {
    public static let collectionName = "captures"
    public let id: CaptureID
    public var revision: Revision
    public var updatedAt: Date
    public var kind: CaptureKind
    public let text: String?
    public let url: String?
    public var channel: CaptureChannel
    public var principal: Principal
    public var capturedAt: Date
    /// The client's stable request identity, used to deduplicate retried captures.
    public var requestID: String?
    public var processing: CaptureProcessing
    public var resultingIdeaID: IdeaID?
    public var resultingNewsID: NewsID?

    public init(
        id: CaptureID = .random(), kind: CaptureKind, text: String?, url: String?, channel: CaptureChannel,
        principal: Principal, requestID: String?, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.kind = kind
        self.text = text
        self.url = url
        self.channel = channel
        self.principal = principal
        self.capturedAt = now
        self.requestID = requestID
        self.processing = .saved
        self.resultingIdeaID = nil
        self.resultingNewsID = nil
    }
}
