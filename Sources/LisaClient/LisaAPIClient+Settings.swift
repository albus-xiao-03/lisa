// Settings routes of the typed client: preferences, source status and the owner-data export.

import Foundation
import LisaAPIContract

extension LisaAPIClient {
    /// `GET /v1/preferences`: the preferences this caller may read.
    public func preferences() async throws(ClientError) -> [PreferenceDTO] {
        try await call(.preferences, returning: [PreferenceDTO].self)
    }

    /// `PATCH /v1/preferences`: applies the changes in order; the first refused change stops the request. Returns the
    /// changed preferences.
    public func updatePreferences(
        _ request: PreferencesPatchRequest, requestID: String? = nil
    ) async throws(ClientError) -> [PreferenceDTO] {
        try await call(.updatePreferences, body: encode(request), requestID: requestID, returning: [PreferenceDTO].self)
    }

    /// `GET /v1/sources/status`: the health and freshness of every source.
    public func sourcesStatus() async throws(ClientError) -> [SourceStatusDTO] {
        try await call(.sourcesStatus, returning: [SourceStatusDTO].self)
    }

    /// `GET /v1/export`: the owner-data export document (format `lisa-export`), as the JSON bytes the host produced.
    public func export() async throws(ClientError) -> Data {
        try await send(.export).body
    }
}
