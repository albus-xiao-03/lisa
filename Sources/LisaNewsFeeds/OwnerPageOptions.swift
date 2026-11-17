// Bounds for one owner-initiated page retrieval: page size, extracted text length, time and redirects.

import LisaHTTPSources

/// Per-retrieval bounds (OPS-02). Every value is clamped to a safe range when used.
public struct OwnerPageOptions: Hashable, Sendable {
    /// The largest page accepted, in bytes.
    public var maxPageBytes: Int
    /// The most characters of text kept from a page.
    public var maxTextCharacters: Int
    /// The time allowed for the whole retrieval, redirects included; each exchange also gets at most this long.
    public var timeoutSeconds: Double
    /// The time allowed for connection setup (DNS, TCP, TLS).
    public var connectTimeoutSeconds: Double
    /// The most redirects followed; each hop is re-checked by the URL and address policy.
    public var maxRedirects: Int

    public init(
        maxPageBytes: Int = 2_000_000, maxTextCharacters: Int = 100_000, timeoutSeconds: Double = 20,
        connectTimeoutSeconds: Double = 10, maxRedirects: Int = 3
    ) {
        self.maxPageBytes = maxPageBytes
        self.maxTextCharacters = maxTextCharacters
        self.timeoutSeconds = timeoutSeconds
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.maxRedirects = maxRedirects
    }

    /// The fetch bounds; a page retrieval never uses stored validators.
    var bounds: FetchBounds {
        let timeout = timeoutSeconds.isFinite ? min(max(timeoutSeconds, 1), 300) : 20
        let connect = connectTimeoutSeconds.isFinite ? min(max(connectTimeoutSeconds, 1), 120) : 10
        return FetchBounds(
            maxBytes: min(max(1, maxPageBytes), 50_000_000), timeoutSeconds: timeout,
            connectTimeoutSeconds: min(connect, timeout), deadlineSeconds: timeout,
            maxRedirects: min(max(0, maxRedirects), 10), validatorLifetimeSeconds: 0)
    }

    /// The text bound, clamped.
    var textLimit: Int { min(max(1, maxTextCharacters), 1_000_000) }
}
