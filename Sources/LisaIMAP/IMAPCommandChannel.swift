// Runs one IMAP command over the authenticated session: sends it with Lisa's own tag, then reads, frames and parses
// responses until its tagged completion, within the framing limits, the command and pass deadlines and cancellation.

import Foundation
import LisaCurl
import LisaRedaction

/// How long a command may take.
enum IMAPCommandWait: Hashable, Sendable {
    /// The complete response within the command timeout: EXAMINE, UID SEARCH and the size probe.
    case completeResponse
    /// More bytes at least every command timeout, for message transfers; the pass deadline bounds the total.
    case steadyProgress
}

/// The tagged completion of a command.
struct IMAPCompletion: Hashable, Sendable {
    var status: IMAPStatus
    var text: IMAPStatusText
}

/// One command at a time over an `IMAPByteStream`, on the pass's thread. Not thread-safe.
final class IMAPCommandChannel {
    /// libcurl tags its commands with one letter and a counter (`A001`, lib/imap.c imap_sendf), so Lisa's tags
    /// cannot collide with them.
    static let tagPrefix = "lisa"
    static let receiveChunkBytes = 65_536

    private let stream: any IMAPByteStream
    let timing: IMAPPassTiming
    private let cancellation: IMAPCancellationFlag
    private let secret: Sensitive<String>
    private var framer = IMAPResponseFramer(limits: IMAPPassLimits.smallResponses)
    private let parseLimits = IMAPParseLimits()
    /// Responses that arrived after a command's completion, in the same read; they are handled first next time.
    private var pending: [IMAPRawResponse] = []
    private var tagNumber = 0
    /// The tag of the command in progress, or of the last one.
    private(set) var currentTag = ""
    /// The commands sent, without tags, in order. They contain no secrets.
    private(set) var sentCommands: [String] = []
    /// Whether the last command ended with its own tagged completion, so the stream is still in step with the server.
    private(set) var isInSync = true
    /// The longest wait for the reply to LOGOUT.
    static let logoutSeconds = 5

    init(
        stream: any IMAPByteStream, timing: IMAPPassTiming, cancellation: IMAPCancellationFlag,
        secret: Sensitive<String>
    ) {
        self.stream = stream
        self.timing = timing
        self.cancellation = cancellation
        self.secret = secret
    }

    /// Sends `command` and passes every untagged response to `handle` until the command completes. A BYE, a
    /// continuation request or another tag's completion ends the pass.
    func run(
        _ command: IMAPCommand, framing: IMAPFramingLimits, wait: IMAPCommandWait,
        handle: (IMAPResponse) throws(IMAPPassFailure) -> Void
    ) throws(IMAPPassFailure) -> IMAPCompletion {
        if cancellation.isCancelled { throw .cancelled }
        guard isInSync else { throw .failed(.internalError, "a command was sent after the session lost step") }
        isInSync = false
        framer.setLimits(framing)
        tagNumber += 1
        currentTag = "\(Self.tagPrefix)\(tagNumber)"
        let start = timing.now
        let commandDeadline = timing.deadline(from: start)
        if timing.hasReached(commandDeadline.instant) {
            throw IMAPFailureClassification.streamFailure(
                .connectionLost("no time left"), during: command, timeout: commandDeadline.cause, timing: timing,
                midLiteral: false)
        }
        do {
            try stream.send(
                command.line(tag: currentTag), deadline: timing.date(for: commandDeadline.instant),
                isCancelled: { cancellation.isCancelled })
        } catch {
            throw failure(error, during: command, deadline: commandDeadline)
        }
        sentCommands.append(command.text)
        while true {
            while !pending.isEmpty {
                let raw = pending.removeFirst()
                if let completion = try process(raw, command: command, handle: handle) {
                    return completion
                }
            }
            let deadline = wait == .completeResponse ? commandDeadline : timing.deadline(from: timing.now)
            let bytes: [UInt8]
            do {
                bytes = try stream.receive(
                    maxBytes: Self.receiveChunkBytes, deadline: timing.date(for: deadline.instant),
                    isCancelled: { cancellation.isCancelled })
            } catch {
                throw failure(error, during: command, deadline: deadline)
            }
            do {
                pending = try framer.feed(bytes)
            } catch {
                throw IMAPFailureClassification.protocolFailure(error, during: command)
            }
        }
    }

    /// Handles one response; returns the completion when it is this command's.
    private func process(
        _ raw: IMAPRawResponse, command: IMAPCommand, handle: (IMAPResponse) throws(IMAPPassFailure) -> Void
    ) throws(IMAPPassFailure) -> IMAPCompletion? {
        let response: IMAPResponse
        do {
            response = try IMAPResponseParser.parse(raw, limits: parseLimits)
        } catch {
            throw IMAPFailureClassification.protocolFailure(error, during: command)
        }
        switch response {
        case .tagged(let tag, let status, let text):
            guard tag == currentTag else {
                throw .failed(.parse, "the IMAP server completed a command Lisa did not send (during \(command.name))")
            }
            isInSync = true
            return IMAPCompletion(status: status, text: text)
        case .bye(let text):
            throw .failed(
                .network,
                IMAPServerText.describe(
                    "the IMAP server closed the session during \(command.name)", code: text.code, text: text.text,
                    withholdingIfContains: secret))
        case .continuation:
            throw .failed(
                .parse, "the IMAP server asked for a continuation during \(command.name), which Lisa never requests")
        case .preauth:
            throw .failed(.parse, "the IMAP server sent PREAUTH after login (during \(command.name))")
        default:
            try handle(response)
            return nil
        }
    }

    /// Ends the session with LOGOUT, best effort: only when the stream is in step, within `logoutSeconds` and the
    /// pass deadline, and ignoring any failure. The server answers BYE and closes (RFC 9051 §6.1.3).
    func logout() {
        guard isInSync, !cancellation.isCancelled else { return }
        let limit = timing.now.advanced(by: .seconds(min(Self.logoutSeconds, timing.commandSeconds)))
        let deadline = min(limit, timing.passDeadline)
        guard !timing.hasReached(deadline) else { return }
        isInSync = false
        tagNumber += 1
        currentTag = "\(Self.tagPrefix)\(tagNumber)"
        do {
            try stream.send(
                IMAPCommand.logout.line(tag: currentTag), deadline: timing.date(for: deadline),
                isCancelled: { cancellation.isCancelled })
            sentCommands.append(IMAPCommand.logout.text)
            framer.setLimits(IMAPPassLimits.smallResponses)
            while true {
                for raw in pending {
                    if case .tagged(let tag, _, _)? = try? IMAPResponseParser.parse(raw, limits: parseLimits),
                        tag == currentTag
                    {
                        return
                    }
                }
                pending = []
                let bytes = try stream.receive(
                    maxBytes: Self.receiveChunkBytes, deadline: timing.date(for: deadline),
                    isCancelled: { cancellation.isCancelled })
                pending = try framer.feed(bytes)
            }
        } catch {
            // Best effort: the server may close the connection right after BYE.
        }
    }

    private func failure(
        _ error: CurlMailFailure, during command: IMAPCommand,
        deadline: (instant: ContinuousClock.Instant, cause: IMAPTimeoutCause)
    ) -> IMAPPassFailure {
        let timedOut = timing.hasReached(deadline.instant)
        return IMAPFailureClassification.streamFailure(
            error, during: command, timeout: timedOut ? deadline.cause : nil, timing: timing,
            midLiteral: framer.isReadingLiteral)
    }
}
