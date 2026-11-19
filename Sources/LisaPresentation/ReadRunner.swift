// Running one read for a screen: the load state it produces and the connectivity it shows.

import Foundation
import LisaClient

/// Turns one read from the host into a screen's next `LoadState`, and reports what it showed about the connection.
@MainActor
enum ReadRunner {
    /// Runs `read`.
    ///
    /// - A value from the host or from the cache is loaded; a cached value carries the host's error, which is reported.
    /// - A failure keeps `previous` on screen as no longer current, except when the device is not paired or was
    ///   removed: then the owner's data is dropped from the screen as well as from the cache.
    static func load<Value: Sendable>(
        previous: ReadResult<Value>?, contacts: (any HostContactReporting)?,
        _ read: () async throws(ClientError) -> ReadResult<Value>
    ) async -> LoadState<Value> {
        do throws(ClientError) {
            let result = try await read()
            await contacts?.record(result.hostError.flatMap(HostContact.init) ?? .reached)
            return .loaded(result)
        } catch {
            if let contact = HostContact(error) { await contacts?.record(contact) }
            let failure = LoadFailure(error)
            return .failed(failure, previous: failure.hidesData ? nil : previous)
        }
    }
}
