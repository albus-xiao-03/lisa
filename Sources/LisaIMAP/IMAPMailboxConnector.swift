// Lisa's IMAP mailbox connector (MAIL-01, MAIL-02, INGEST-01): read-only, incremental retrieval of a dedicated
// mailbox over libcurl's authenticated session, one bounded pass per fetch on a dedicated thread.

import Foundation
import LisaCurl
import LisaDomain
import LisaPorts
import LisaRedaction
import LisaSecrets
import LisaTime

/// Reads new messages from Lisa's mailbox folder.
///
/// - Only EXAMINE, UID SEARCH, UID FETCH with `UID`, `RFC822.SIZE` and `BODY.PEEK[]`, and a final LOGOUT are sent,
///   so no flag, message or folder changes; the session is refused unless the server confirms read-only access.
/// - Items are RFC 5322 messages identified as `imap:<uidvalidity>:<uid>`. The cursor holds the folder's UIDVALIDITY
///   and the last UID handled; when UIDVALIDITY changes the folder is read again and ingestion recognizes stored
///   messages by Message-ID.
/// - Each pass honors `SyncLimits` (items, bytes, time) plus per-command timeouts and task cancellation. Messages
///   above the size limit are not downloaded; each is named in the batch's capability notes.
/// - Any failure is a classified `ConnectorError` (or `CancellationError`), never a partial or empty batch, and the
///   cursor does not move. Errors never contain the password.
public struct IMAPMailboxConnector: SourceConnector {
    public let kind: SourceKind = .mailbox
    public let settings: IMAPMailboxSettings
    private let secrets: any SecretStore
    private let clock: any WallClock

    /// The password is resolved from `secrets` at the start of every pass, never here.
    public init(settings: IMAPMailboxSettings, secrets: any SecretStore, clock: any WallClock) {
        self.settings = settings
        self.secrets = secrets
        self.clock = clock
    }

    /// Checks the settings without resolving the secret or contacting the server.
    public func validateConfiguration() throws {
        if let problem = settings.configurationProblem { throw ConnectorError(.configuration, problem) }
    }

    /// One pass: connect and log in, read the batch after `cursor`, and close. `cursor` is a value an earlier batch
    /// returned, or nil to start from the folder's first message.
    public func fetch(cursor: String?, limits: SyncLimits) async throws -> FetchBatch {
        try validateConfiguration()
        if let problem = IMAPMailboxSettings.limitsProblem(limits) { throw ConnectorError(.configuration, problem) }
        try Task.checkCancellation()
        let request = IMAPPassRequest(
            settings: settings, password: try resolvePassword(), cursor: cursor, limits: limits, clock: clock)
        let cancellation = IMAPCancellationFlag()
        let result = await CurlWorkerThread.run(
            name: "lisa.imap", onCancel: { cancellation.cancel() },
            { IMAPPassRunner.run(request, cancellation: cancellation) })
        switch result {
        case .success(let batch): return batch
        case .failure(let failure): throw failure.thrownError
        }
    }

    private func resolvePassword() throws -> Sensitive<String> {
        let password: Sensitive<String>
        do {
            password = try secrets.secret(for: settings.password)
        } catch let error as SecretStoreError {
            throw ConnectorError(.configuration, "the mailbox password could not be resolved: \(error)")
        } catch {
            throw ConnectorError(.configuration, "the mailbox password \(settings.password) could not be resolved")
        }
        if let problem = IMAPMailboxSettings.passwordProblem(password.revealed) {
            throw ConnectorError(.configuration, problem)
        }
        return password
    }
}
