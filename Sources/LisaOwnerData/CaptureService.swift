// Captures (IDEA-01, NEWS-04): saved immediately, idempotent by request ID, and linked to the idea or news item made.

import Foundation
import LisaDomain
import LisaLogging
import LisaPorts
import LisaTime

/// A capture as submitted by the CLI, an app, Siri or the API.
public struct CaptureRequest: Hashable, Sendable {
    public var kind: CaptureKind
    public var text: String?
    public var url: String?
    /// A title supplied with shared content (for example by the share sheet).
    public var title: String?
    public var channel: CaptureChannel
    /// The client's stable request identity; repeating it returns the original capture.
    public var requestID: String?

    public init(
        kind: CaptureKind, text: String? = nil, url: String? = nil, title: String? = nil, channel: CaptureChannel,
        requestID: String? = nil
    ) {
        self.kind = kind
        self.text = text
        self.url = url
        self.title = title
        self.channel = channel
        self.requestID = requestID
    }
}

/// The saved capture and what it produced.
public struct CaptureResult: Sendable {
    public var capture: Capture
    public var idea: Idea?
    public var news: NewsItem?
    /// False when the request ID matched an earlier capture, which is returned unchanged.
    public var created: Bool
}

/// Saves captures. An idea is stored as written before any interpretation, so capture never depends on a model.
public final class CaptureService: Sendable {
    public static let maxTextCharacters = 20_000
    public static let maxURLCharacters = 2_048
    public static let maxRequestIDCharacters = 128
    /// The configuration key of the source that owns manually shared content.
    public static let manualSourceKey = "manual-capture"

    private let store: any RecordStore
    private let clock: any WallClock
    private let logger: Logger

    public init(store: any RecordStore, clock: any WallClock, logger: Logger) {
        self.store = store
        self.clock = clock
        self.logger = logger
    }

    public func capture(_ request: CaptureRequest, by principal: Principal) throws -> CaptureResult {
        guard principal != .model else { throw DomainError.notPermitted("models cannot create captures") }
        let text = request.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let url = request.url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try Self.validate(request, text: text, url: url)
        let now = clock.now()
        let result = try store.write { tx -> CaptureResult in
            if let requestID = request.requestID,
                let existing = try tx.first(Capture.self, RecordQuery.all.filter("request_id", equals: requestID))
            {
                return CaptureResult(
                    capture: existing, idea: try existing.resultingIdeaID.flatMap { try tx.get(Idea.self, id: $0) },
                    news: try existing.resultingNewsID.flatMap { try tx.get(NewsItem.self, id: $0) }, created: false)
            }
            var capture = Capture(
                kind: request.kind, text: text, url: url, channel: request.channel, principal: principal,
                requestID: request.requestID, now: now)
            var idea: Idea?
            var news: NewsItem?
            switch request.kind {
            case .idea:
                let saved = try tx.insert(
                    Idea(originalCapture: text ?? url ?? "", captureID: capture.id, now: now))
                capture.resultingIdeaID = saved.id
                idea = saved
            case .text, .link, .sharedAppleNews:
                let item = try Self.sharedNews(for: capture, title: request.title, now: now, in: tx)
                capture.resultingNewsID = item.id
                news = item
            }
            capture.processing = .processed
            let stored = try tx.insert(capture)
            try tx.insert(
                AuditEvent(
                    action: "capture.saved", actor: principal, at: now, affected: [stored.id.rawValue],
                    outcome: .succeeded, detail: "kind=\(request.kind.rawValue) channel=\(request.channel.rawValue)"))
            return CaptureResult(capture: stored, idea: idea, news: news, created: true)
        }
        if result.created {
            logger.info(
                "capture saved",
                ["capture": .public(result.capture.id.rawValue), "kind": .public(request.kind.rawValue)])
        }
        return result
    }

    static func validate(_ request: CaptureRequest, text: String?, url: String?) throws {
        if let text, text.count > maxTextCharacters {
            throw DomainError.invalidValue(field: "text", reason: "longer than \(maxTextCharacters) characters")
        }
        if let requestID = request.requestID, requestID.isEmpty || requestID.count > maxRequestIDCharacters {
            throw DomainError.invalidValue(
                field: "requestID", reason: "must be 1 to \(maxRequestIDCharacters) characters")
        }
        if let url {
            guard url.count <= maxURLCharacters, let parsed = URL(string: url),
                let scheme = parsed.scheme?.lowercased(), scheme == "https" || scheme == "http", parsed.host != nil
            else { throw DomainError.invalidValue(field: "url", reason: "must be an http or https address") }
        }
        switch request.kind {
        case .idea, .text:
            guard text != nil || url != nil else { throw DomainError.invalidValue(field: "text", reason: "is empty") }
        case .link, .sharedAppleNews:
            guard url != nil else {
                throw DomainError.invalidValue(field: "url", reason: "is required for shared links")
            }
        }
    }

    /// The news item for shared content. Sharing the same address twice links both captures to one item.
    static func sharedNews(for capture: Capture, title: String?, now: Date, in tx: any RecordWriting) throws -> NewsItem
    {
        let source = try SourceRegistry.ensureSource(
            kind: .manualCapture, name: "Shared by the owner", configurationKey: manualSourceKey, now: now, in: tx)
        let dedupKey = capture.url.map { "shared:\(normalizedAddress($0))" } ?? "shared-text:\(capture.id.rawValue)"
        if let existing = try tx.first(NewsItem.self, RecordQuery.all.filter("dedup_key", equals: dedupKey)) {
            return existing
        }
        let excerpt = String((capture.text ?? capture.url ?? "").prefix(280))
        let evidence = try tx.insert(
            Evidence(
                kind: .capture, sourceID: source.id, externalID: capture.id.rawValue, capturedAt: now, excerpt: excerpt)
        )
        let displayTitle =
            title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? capture.text.map { String($0.prefix(120)) } ?? capture.url ?? "Shared item"
        return try tx.insert(
            NewsItem(
                sourceID: source.id, originalURL: capture.url, title: displayTitle, accessibleText: capture.text,
                boundary: capture.text == nil ? .titleOnly : .sharedText, publishedAt: nil, retrievedAt: now,
                isSharedContent: true, sharedFrom: capture.kind == .sharedAppleNews ? "Apple News" : nil,
                dedupKey: dedupKey, evidenceID: evidence.id))
    }

    /// Lower-cases the scheme and host and drops a fragment, so trivially different spellings share one item.
    static func normalizedAddress(_ address: String) -> String {
        guard var components = URLComponents(string: address) else { return address }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.string ?? address
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
