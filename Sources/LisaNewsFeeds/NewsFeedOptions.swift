// Bounds for one news feed: document size, request and connection time, redirects, and how long stored validators
// are used before a full download.

import LisaHTTPSources
import LisaPorts

/// Per-feed bounds (OPS-02). Every value is clamped to a safe range when used.
public struct NewsFeedOptions: Hashable, Sendable {
    /// The largest feed document accepted, in bytes. Defaults to news ingestion's own feed limit.
    public var maxDocumentBytes: Int
    /// The time allowed for each exchange (one redirect hop), including connection setup.
    public var requestTimeoutSeconds: Double
    /// The time allowed for connection setup (DNS, TCP, TLS).
    public var connectTimeoutSeconds: Double
    /// The most redirects followed; each hop is re-checked by the URL and address policy.
    public var maxRedirects: Int
    /// How long the validators of a full download are used for conditional requests. After this, the next fetch
    /// downloads the feed again, so a server that wrongly keeps answering "not modified" cannot hide new entries for
    /// longer than this.
    public var fullRefreshSeconds: Int

    public init(
        maxDocumentBytes: Int = 10_000_000, requestTimeoutSeconds: Double = 30, connectTimeoutSeconds: Double = 10,
        maxRedirects: Int = 3, fullRefreshSeconds: Int = 24 * 3_600
    ) {
        self.maxDocumentBytes = maxDocumentBytes
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.maxRedirects = maxRedirects
        self.fullRefreshSeconds = fullRefreshSeconds
    }

    /// The bounds for one fetch under the pass's `limits`: never more bytes or time than the pass allows.
    func bounds(for limits: SyncLimits) -> FetchBounds {
        let deadline = Double(min(max(1, limits.timeoutSeconds), 3_600))
        let timeout = min(Self.clamp(requestTimeoutSeconds, 1...600, fallback: 30), deadline)
        return FetchBounds(
            maxBytes: max(1, min(maxDocumentBytes, limits.maxBytes)), timeoutSeconds: timeout,
            connectTimeoutSeconds: min(Self.clamp(connectTimeoutSeconds, 1...120, fallback: 10), timeout),
            deadlineSeconds: deadline, maxRedirects: min(max(0, maxRedirects), 10),
            validatorLifetimeSeconds: Double(min(max(0, fullRefreshSeconds), 7 * 86_400)))
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
