// Runs one pass on the dedicated thread: opens the libcurl session within the pass's time limit, checks the hand-over,
// runs the commands, sends LOGOUT when the session is still in step, and closes the connection.

import Foundation
import LisaCurl
import LisaPorts
import LisaRedaction
import LisaTime

/// Everything a pass needs, resolved before the thread starts.
struct IMAPPassRequest: Sendable {
    let settings: IMAPMailboxSettings
    let password: Sensitive<String>
    let cursor: String?
    let limits: SyncLimits
    let clock: any WallClock
}

/// The blocking body of a pass. CurlIMAPSession is not thread-safe, so it is opened, used and closed here only.
enum IMAPPassRunner {
    static func run(_ request: IMAPPassRequest, cancellation: IMAPCancellationFlag)
        -> Result<FetchBatch, IMAPPassFailure>
    {
        do {
            return .success(try perform(request, cancellation: cancellation))
        } catch {
            return .failure(error)
        }
    }

    private static func perform(_ request: IMAPPassRequest, cancellation: IMAPCancellationFlag)
        throws(IMAPPassFailure) -> FetchBatch
    {
        let settings = request.settings
        guard let folder = IMAPMailboxName(settings.folder) else {
            throw .failed(.configuration, "the IMAP folder must be 1 to 255 printable ASCII characters")
        }
        let timing = IMAPPassTiming(
            passSeconds: request.limits.timeoutSeconds, commandSeconds: settings.commandTimeoutSeconds)
        if cancellation.isCancelled { throw .cancelled }
        let session: CurlIMAPSession
        do {
            session = try CurlIMAPSession.open(
                server: server(for: settings, passSeconds: timing.passSeconds), username: settings.username,
                password: request.password.revealed, isCancelled: { cancellation.isCancelled })
        } catch {
            throw IMAPFailureClassification.connectFailure(error, passTimedOut: timing.hasReached(timing.passDeadline))
        }
        defer { session.close() }
        if cancellation.isCancelled { throw .cancelled }
        try IMAPHandOverCheck.verify(session.connectTranscript)
        let channel = IMAPCommandChannel(
            stream: session, timing: timing, cancellation: cancellation, secret: request.password)
        // Runs before the session's close (defers run in reverse order).
        defer { channel.logout() }
        let start: IMAPStartingPoint =
            switch request.cursor.map(IMAPSyncCursor.parse) {
            case nil: .beginning
            case .some(nil): .unreadableCursor
            case .some(.some(let cursor)): .cursor(cursor)
            }
        let limits = IMAPPassLimits(
            maxItems: request.limits.maxItems, maxBytes: request.limits.maxBytes,
            maxMessageBytes: settings.maxMessageBytes)
        return try IMAPFetchPass(
            channel: channel, folder: folder, start: start, limits: limits, clock: request.clock,
            secret: request.password
        ).run()
    }

    /// The server as libcurl sees it. Its connect phase lasts at most the connect timeout plus four response
    /// timeouts (CurlIMAPSession), so both are derived from the pass limit to keep login inside the pass.
    static func server(for settings: IMAPMailboxSettings, passSeconds: Int) -> CurlMailServer {
        let connectSeconds = min(settings.connectTimeoutSeconds, Double(passSeconds) / 2)
        let loginBudget = Int((Double(passSeconds) - connectSeconds) / 4)
        let responseSeconds = max(1, min(settings.commandTimeoutSeconds, loginBudget))
        return CurlMailServer(
            host: settings.host, port: settings.port, security: settings.security, addresses: settings.addresses,
            connectTimeoutSeconds: connectSeconds, responseTimeoutSeconds: responseSeconds,
            trustStorePath: settings.trustStorePath)
    }
}
