// The daily model-request budget (MODEL-01): every request to the provider, including a repair attempt, is reserved
// first, and the count survives restarts. The store behind it belongs to the host.

/// Reserves model requests against a per-day limit.
public protocol ModelRequestBudget: Sendable {
    /// Reserves one request for the current day. Returns `false` once the day's `limit` is reached; throws when the
    /// count cannot be read or recorded, in which case no request may be sent.
    func reserve(limit: Int) throws -> Bool
}
