// The configured data-sharing policy and usage limits that every model request must satisfy (MODEL-04, SEC-03).

/// What may be sent to a model. The default sends nothing outside the process.
public enum ModelDataSharing: String, Codable, Sendable, CaseIterable {
    /// Only the in-process deterministic provider may be used.
    case none
    /// Explicitly configured local or private-network endpoints may receive content.
    case localOnly
    /// A remote endpoint may receive minimized content (addresses, numbers and links removed).
    case remoteMinimized

    /// Whether content may be sent to a provider at `location`.
    public func permits(_ location: ModelLocation) -> Bool {
        switch (self, location) {
        case (_, .inProcess): true
        case (.localOnly, .localNetwork), (.remoteMinimized, .localNetwork), (.remoteMinimized, .remote): true
        default: false
        }
    }
}

/// Bounds on model use (OPS-02).
public struct ModelUsageLimits: Hashable, Codable, Sendable {
    public var maxInputCharacters: Int
    public var maxOutputTokens: Int
    public var maxRequestsPerDay: Int
    public var maxResponseBytes: Int
    public var maxItems: Int

    public init(
        maxInputCharacters: Int = 12_000, maxOutputTokens: Int = 1_200, maxRequestsPerDay: Int = 500,
        maxResponseBytes: Int = 65_536, maxItems: Int = 25
    ) {
        self.maxInputCharacters = maxInputCharacters
        self.maxOutputTokens = maxOutputTokens
        self.maxRequestsPerDay = maxRequestsPerDay
        self.maxResponseBytes = maxResponseBytes
        self.maxItems = maxItems
    }
}
