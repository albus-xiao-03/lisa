// SMTP submission over TLS (EMAIL-01): libcurl connects with implicit TLS or required STARTTLS, authenticates,
// sends MAIL FROM, RCPT TO and DATA, dot-stuffs the message and ends it. The outcome distinguishes "not accepted"
// (safe to retry) from "may have been accepted" (never resent automatically).

import CCurl
import CCurlShim
import Foundation

/// One message to submit.
public struct CurlSMTPMessage: Sendable {
    /// The name sent with EHLO. Without it libcurl would send this machine's host name.
    public var heloName: String
    /// The envelope sender.
    public var from: String
    /// The envelope recipients. One refused recipient fails the whole submission.
    public var recipients: [String]
    /// The complete RFC 5322 message with CRLF line endings, not dot-stuffed (libcurl does that).
    public var data: Data
    /// The limit for the whole submission, connection included.
    public var timeoutSeconds: Double

    public init(heloName: String, from: String, recipients: [String], data: Data, timeoutSeconds: Double = 60) {
        self.heloName = heloName
        self.from = from
        self.recipients = recipients
        self.data = data
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Submits messages with libcurl. Each submission uses a new connection.
public enum CurlSMTPSubmission {
    /// Submits `message`; returns the server's final reply code (250) when the message was accepted.
    public static func submit(
        _ message: CurlSMTPMessage, server: CurlMailServer, username: String, password: String
    ) async throws(CurlMailFailure) -> Int {
        let cancellation = CurlCancellation()
        let cancel: @Sendable () -> Void = { cancellation.cancel() }
        let result = await CurlWorkerThread.run(name: "lisa.curl.smtp", onCancel: cancel) {
            perform(message, server: server, username: username, password: password, cancellation: cancellation)
        }
        return try result.get()
    }

    static func perform(
        _ message: CurlSMTPMessage, server: CurlMailServer, username: String, password: String,
        cancellation: CurlCancellation
    ) -> Result<Int, CurlMailFailure> {
        guard !message.recipients.isEmpty else { return .failure(.refused("there are no recipients")) }
        guard server.isWellFormed else { return .failure(.refused("the SMTP server's host name or port is not valid")) }
        let addresses = [message.from] + message.recipients
        guard addresses.allSatisfy(isSafeAddress), isSafeHeloName(message.heloName) else {
            return .failure(.refused("an address or the EHLO name contains characters that are not allowed"))
        }
        let easy: CurlEasy
        do { easy = try CurlEasy() } catch { return .failure(.refused(error.description)) }
        let transfer = CurlTransfer(maxBodyBytes: 0, maxHeaderBytes: 262_144, recordsLines: true)
        let gate = CurlAddressGate(policy: server.addresses, maxRequests: 1)
        let upload = CurlUpload(message.data)
        var recipients: CurlStringList?
        // libcurl may send QUIT and call the header and progress callbacks while cleaning up, so every callback
        // context, and the recipient list it still references, stays alive until cleanup returns.
        defer { withExtendedLifetime((transfer, gate, upload, cancellation, recipients)) { easy.cleanup() } }
        do {
            let path =
                message.heloName.addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-"))) ?? ""
            try CurlMailOptions.apply(
                to: easy, server: server, scheme: "smtp", path: path, username: username, password: password,
                gate: gate, transfer: transfer, cancellation: cancellation, totalTimeoutSeconds: message.timeoutSeconds)
            try easy.set(CURLOPT_MAIL_FROM, "<\(message.from)>")
            let list = try CurlStringList(message.recipients.map { "<\($0)>" })
            recipients = list
            try easy.set(CURLOPT_MAIL_RCPT, pointer: UnsafeMutableRawPointer(list.head))
            try easy.set(CURLOPT_UPLOAD, 1)
            try easy.set(CURLOPT_INFILESIZE_LARGE, offset: Int64(message.data.count))
            try CurlMailOptions.require(lisa_curl_set_read_callback(easy.handle, curlReadUpload, upload.userdata))
        } catch {
            return .failure(.refused("the submission could not be prepared: \(error.description)"))
        }
        let code = curl_easy_perform(easy.handle)
        let reply = easy.long(CURLINFO_RESPONSE_CODE) ?? 0
        if code == CURLE_OK { return .success(reply) }
        let text = String(cString: curl_easy_strerror(code))
        // A 4xx or 5xx reply is the server refusing; nothing was accepted, whatever the stage.
        if (400...599).contains(reply), code != CURLE_LOGIN_DENIED {
            return .failure(.serverRefused(code: reply, text))
        }
        // Once the whole message was handed over, a lost connection or timeout leaves the outcome unknown: the
        // server may have accepted the message before its reply was lost.
        if upload.finished {
            return .failure(.uncertain(cancellation.isCancelled ? "cancelled after the message was sent" : text))
        }
        if upload.started, code != CURLE_LOGIN_DENIED {
            return .failure(.connectionLost("the connection ended before the message was complete: \(text)"))
        }
        return .failure(
            CurlMailOptions.setupFailure(code, message: text, gate: gate, cancelled: cancellation.isCancelled))
    }

    /// No CR, LF, NUL, angle brackets or spaces, which libcurl would pass through verbatim into SMTP commands.
    static func isSafeAddress(_ address: String) -> Bool {
        !address.isEmpty && address.utf8.count <= 320 && address.utf8.contains(0x40)
            && !address.utf8.contains { $0 <= 0x20 || $0 == 0x7F || $0 == 0x3C || $0 == 0x3E }
    }

    static func isSafeHeloName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 253
            && name.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x2E
                    || $0 == 0x2D
            }
    }
}

/// The message bytes libcurl's read callback hands out, and how far it got.
final class CurlUpload {
    private let data: Data
    private var offset = 0
    private(set) var started = false
    private(set) var finished = false

    init(_ data: Data) { self.data = data }

    var userdata: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    /// Copies the next bytes. `finished` is set as soon as the last byte is handed over: with the size declared,
    /// libcurl may never ask again for the end of the data, and it sends the end-of-data marker right after.
    func fill(_ buffer: UnsafeMutableRawBufferPointer) -> Int {
        started = true
        let count = min(buffer.count, data.count - offset)
        if count > 0 {
            data.copyBytes(to: buffer.bindMemory(to: UInt8.self), from: offset..<(offset + count))
            offset += count
        }
        if offset == data.count { finished = true }
        return count
    }
}

/// libcurl read callback: the next message bytes for the CurlUpload in `userdata`; 0 at the end.
let curlReadUpload: lisa_curl_data_callback = { buffer, size, count, userdata in
    guard let userdata, let buffer else { return 0 }
    let upload = Unmanaged<CurlUpload>.fromOpaque(userdata).takeUnretainedValue()
    return upload.fill(UnsafeMutableRawBufferPointer(start: buffer, count: size * count))
}
