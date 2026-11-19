// Query parameters of the v1 read routes: local dates, the task status filter and pagination, checked before sending.

import Foundation
import LisaAPIContract

/// Builds and validates query parameters.
enum RequestQuery {
    /// The local-date parameter of the rundown and brief routes (`YYYY-MM-DD`).
    static let dateParameter = "date"
    /// The status filter of the task list.
    static let statusParameter = "status"
    /// The lifecycle filter of the idea list.
    static let lifecycleParameter = "lifecycle"
    /// The state filter of the proposal and reminder lists: a comma-separated list.
    static let stateParameter = "state"

    /// `state=a,b`, or no parameter for the host's default states.
    static func states(_ states: [String]) throws(ClientError) -> [String: String] {
        guard !states.isEmpty else { return [:] }
        guard states.allSatisfy({ !$0.isEmpty && !$0.contains(",") }) else {
            throw .invalidArgument(name: stateParameter, reason: "a state is empty or contains a comma")
        }
        return [stateParameter: states.joined(separator: ",")]
    }

    /// `date=YYYY-MM-DD`, or no parameter for the host's current date.
    static func localDate(_ date: String?) throws(ClientError) -> [String: String] {
        guard let date else { return [:] }
        try checkLocalDate(date)
        return [dateParameter: date]
    }

    /// Rejects text that is not a `YYYY-MM-DD` calendar date.
    static func checkLocalDate(_ date: String) throws(ClientError) {
        guard APIDates.isLocalDate(date) else {
            throw .invalidArgument(name: dateParameter, reason: "expected a calendar date such as 2026-11-16")
        }
    }

    /// `limit` and `cursor`, checked against the API's pagination limits.
    static func page(limit: Int?, cursor: String?) throws(ClientError) -> [String: String] {
        var query: [String: String] = [:]
        if let limit {
            guard (1...Pagination.maxLimit).contains(limit) else {
                throw .invalidArgument(name: Pagination.limitParameter, reason: "expected 1 to \(Pagination.maxLimit)")
            }
            query[Pagination.limitParameter] = String(limit)
        }
        if let cursor {
            guard !cursor.isEmpty else {
                throw .invalidArgument(name: Pagination.cursorParameter, reason: "the cursor is empty")
            }
            query[Pagination.cursorParameter] = cursor
        }
        return query
    }
}
