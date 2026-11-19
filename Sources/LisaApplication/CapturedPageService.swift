// Reading the page behind a captured link (NEWS-01, SEC-02): only at the owner's request, once per news item, with the
// page's text, evidence and raw content kept as a feed item's are, and every failure reported instead of stored.

import Foundation
import LisaDomain
import LisaIngestion
import LisaLogging
import LisaPorts
import LisaTime
import Synchronization

/// Reads the pages behind links the owner captured.
///
/// - Only the local owner or a paired device may ask, and only for a `link` capture the owner made. A model, the
///   runtime and the demonstration never can, and links inside text, ideas or other content are never fetched.
/// - A page is read once per news item: asking again is a conflict, and asking while it is being read is a temporary
///   refusal.
/// - A page that was read updates the capture's news item in one transaction: its text, bounded like a feed item's and
///   labeled `pageText` (the item stays `titleOnly` when the page has no readable text); the retrieval time; the page's
///   address; the page's title when the item had only the link as its title; and the item's evidence, which then holds
///   an excerpt and a reference to the raw page, kept under the raw-content retention rules like a feed document.
/// - A page that could not be read leaves the item exactly as it was and keeps nothing from the page. A lasting failure
///   is returned as the outcome; a temporary one is thrown as `CapturedPageError.temporarilyUnavailable`.
/// - Every attempt is audited with its outcome and failure class, never with the address or the page's content.
public final class CapturedPageService: Sendable {
    /// Seconds to wait after a temporary failure when the site named no time.
    public static let defaultRetrySeconds = 60
    /// The longest wait suggested after a temporary failure.
    public static let maxRetrySeconds = 3_600
    /// The longest evidence excerpt, as for feed items.
    public static let maxExcerptCharacters = 280
    /// The longest title kept, as for feed items.
    public static let maxTitleCharacters = 300
    /// The raw-content kind of a retrieved page.
    public static let rawContentKind = "page"

    private let store: any RecordStore
    private let raw: any RawContentStore
    private let clock: any WallClock
    private let logger: Logger
    private let retrieval: any CapturedPageRetrieval
    /// News items whose page is being read. The host is the only writer of its data directory (ARCH-03).
    private let inFlight = Mutex<Set<NewsID>>([])

    /// - Parameter retrieval: reads the pages (the owner page retriever in production).
    public init(
        store: any RecordStore, raw: any RawContentStore, clock: any WallClock, logger: Logger,
        retrieval: any CapturedPageRetrieval
    ) {
        self.store = store
        self.raw = raw
        self.clock = clock
        self.logger = logger
        self.retrieval = retrieval
    }

    /// Refuses every principal except the owner on the host and paired devices, which act for the owner.
    public static func authorize(_ principal: Principal) throws {
        switch principal {
        case .localOwner, .pairedDevice:
            return
        case .model, .runtime, .demonstration:
            throw DomainError.notPermitted(
                "only the owner, on the host or a paired device, can ask Lisa to read a captured link")
        }
    }

    /// Reads the page behind capture `id` and keeps it on the capture's news item.
    ///
    /// - Throws: `DomainError.notPermitted` for a principal other than the owner; `StoreError.notFound` for an unknown
    ///   capture; `CapturedPageError` when the capture's link is never read, its item was deleted, its page was
    ///   already read or is being read, or the page could not be read for a temporary reason.
    public func retrieve(_ id: CaptureID, by principal: Principal) async throws -> CapturedPageOutcome {
        try Self.authorize(principal)
        let capture = try store.read { try $0.require(Capture.self, id: id) }
        try Self.checkRetrievable(capture)
        guard let newsID = capture.resultingNewsID else { throw CapturedPageError.itemMissing }
        guard claim(newsID) else { throw CapturedPageError.inProgress }
        defer { release(newsID) }
        let item = try store.read { try Self.unread(newsID, in: $0) }
        let page: CapturedPage
        do throws(ConnectorError) {
            page = try await retrieval.retrieve(capture)
        } catch {
            return try failed(error, capture: capture, item: item, by: principal)
        }
        return try keep(page, capture: capture, by: principal)
    }

    // MARK: - Eligibility

    /// Refuses captures whose link is never read: ideas, text and Apple News shares, and captures the owner did not
    /// make.
    static func checkRetrievable(_ capture: Capture) throws {
        switch capture.kind {
        case .link:
            break
        case .sharedAppleNews:
            throw CapturedPageError.notRetrievable(
                "Apple News items are kept as shared content and are never retrieved")
        case .idea, .text:
            throw CapturedPageError.notRetrievable(
                "only a captured link is read; links inside ideas and text are never fetched")
        }
        switch capture.principal {
        case .localOwner, .pairedDevice:
            break
        case .runtime, .model, .demonstration:
            throw CapturedPageError.notRetrievable("only a link the owner captured is read")
        }
    }

    /// The news item `id`, provided its page has not been read yet.
    static func unread(_ id: NewsID, in tx: any RecordReading) throws -> NewsItem {
        guard let item = try tx.get(NewsItem.self, id: id) else { throw CapturedPageError.itemMissing }
        guard item.pageURL == nil else { throw CapturedPageError.alreadyRetrieved }
        return item
    }

    private func claim(_ id: NewsID) -> Bool {
        inFlight.withLock { $0.insert(id).inserted }
    }

    private func release(_ id: NewsID) {
        _ = inFlight.withLock { $0.remove(id) }
    }

    // MARK: - Failure

    /// Records a page that could not be read. The item is not touched and nothing from the page is kept.
    private func failed(_ error: ConnectorError, capture: Capture, item: NewsItem, by principal: Principal) throws
        -> CapturedPageOutcome
    {
        let now = clock.now()
        try store.write { tx in
            try tx.insert(
                AuditEvent(
                    action: "capture.page-retrieval-failed", actor: principal, at: now,
                    affected: [capture.id.rawValue, item.id.rawValue], outcome: .failed,
                    detail: "class=\(error.errorClass.rawValue)"))
        }
        logger.notice(
            "captured page not read",
            ["capture": .public(capture.id.rawValue), "class": .public(error.errorClass.rawValue)])
        if error.errorClass.isRetryable {
            throw CapturedPageError.temporarilyUnavailable(error, retryAfterSeconds: Self.retrySeconds(error, now: now))
        }
        return CapturedPageOutcome(
            capture: capture, item: item, failure: error, keptCharacters: 0, textTruncated: false)
    }

    /// Seconds until a retry: the site's own `Retry-After` when it gave one, within bounds.
    static func retrySeconds(_ error: ConnectorError, now: Date) -> Int {
        guard let retryAfter = error.retryAfter else { return defaultRetrySeconds }
        let seconds = retryAfter.timeIntervalSince(now)
        guard seconds.isFinite else { return defaultRetrySeconds }
        return min(max(1, Int(seconds.rounded(.up))), maxRetrySeconds)
    }

    // MARK: - Keeping a page

    /// Keeps a page that was read: the raw page first, then the item and its evidence in one transaction. When the
    /// transaction fails, the raw page is removed again.
    private func keep(_ page: CapturedPage, capture: Capture, by principal: Principal) throws -> CapturedPageOutcome {
        let text = Self.keptText(page.text)
        let ref = try raw.put(page.rawContent, kind: Self.rawContentKind, now: page.retrievedAt)
        let now = clock.now()
        let saved: (item: NewsItem, replacedContent: String?)
        do {
            saved = try store.write { tx in
                try Self.record(
                    page, text: text.value, content: ref, capture: capture.id, by: principal, now: now, in: tx)
            }
        } catch {
            discard(ref)
            throw error
        }
        if let replaced = saved.replacedContent, replaced != ref.value { discard(RawContentRef(replaced)) }
        logger.info(
            "captured page read",
            [
                "capture": .public(capture.id.rawValue), "characters": .count(text.value?.count ?? 0),
                "mediaType": .public(page.mediaType),
            ])
        return CapturedPageOutcome(
            capture: capture, item: saved.item, failure: nil, keptCharacters: text.value?.count ?? 0,
            textTruncated: page.textTruncated || text.cut)
    }

    /// Updates the capture's news item and its evidence, after checking again that the page was not read meanwhile.
    /// Returns the item and the raw-content reference its evidence held before, if any.
    static func record(
        _ page: CapturedPage, text: String?, content: RawContentRef, capture id: CaptureID, by principal: Principal,
        now: Date, in tx: any RecordWriting
    ) throws -> (item: NewsItem, replacedContent: String?) {
        let capture = try tx.require(Capture.self, id: id)
        guard let newsID = capture.resultingNewsID else { throw CapturedPageError.itemMissing }
        var item = try unread(newsID, in: tx)
        let title = page.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = String((text ?? title ?? item.title).prefix(maxExcerptCharacters))
        var replacedContent: String?
        if var evidence = try tx.get(Evidence.self, id: item.evidenceID) {
            replacedContent = evidence.contentRef
            evidence.kind = .news
            evidence.capturedAt = page.retrievedAt
            evidence.excerpt = excerpt
            evidence.contentRef = content.value
            evidence.updatedAt = now
            try tx.update(evidence)
        } else {
            let evidence = try tx.insert(
                Evidence(
                    kind: .news, sourceID: item.sourceID, externalID: id.rawValue, capturedAt: page.retrievedAt,
                    excerpt: excerpt, contentRef: content.value))
            item.evidenceID = evidence.id
        }
        if let title, !title.isEmpty, item.title == item.originalURL {
            item.title = String(title.prefix(maxTitleCharacters))
        }
        if let text {
            item.accessibleText = text
            item.boundary = .pageText
        }
        item.retrievedAt = page.retrievedAt
        item.pageURL = page.finalURL.absoluteString
        item.updatedAt = now
        let saved = try tx.update(item)
        let detail = "mediaType=\(page.mediaType) characters=\(text?.count ?? 0) boundary=\(saved.boundary.rawValue)"
        try tx.insert(
            AuditEvent(
                action: "capture.page-retrieved", actor: principal, at: now,
                affected: [id.rawValue, saved.id.rawValue], outcome: .succeeded, detail: detail))
        return (saved, replacedContent)
    }

    /// The page's text as the item keeps it: at most a feed item's length, marked with "…" when cut; `nil` when
    /// the page has no readable text.
    static func keptText(_ text: String) -> (value: String?, cut: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, false) }
        let limit = NewsBatchProcessor.maxTextCharacters
        guard trimmed.count > limit else { return (trimmed, false) }
        return (String(trimmed.prefix(limit)) + "…", true)
    }

    /// Removes raw content that no record refers to; a failure leaves it to retention.
    private func discard(_ ref: RawContentRef) {
        do {
            try raw.delete(ref)
        } catch {
            logger.warning("unreferenced raw page kept until retention", ["error": .private(String(describing: error))])
        }
    }
}
