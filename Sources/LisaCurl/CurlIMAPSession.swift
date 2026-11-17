// The authenticated IMAP session hand-over (plan §7, option C). libcurl connects, verifies TLS (implicit or
// required STARTTLS) and authenticates in its connect phase; CURLOPT_CONNECT_ONLY then stops before libcurl sends
// any mailbox command, and Lisa speaks its own read-only command subset over curl_easy_send and curl_easy_recv.

import CCurl
import CCurlShim
import Foundation

/// An authenticated IMAP connection. Not thread-safe: open, use and close it on one thread (for example inside
/// `CurlWorkerThread.run`). Closing lets libcurl send its own tagged LOGOUT.
public final class CurlIMAPSession {
    /// The lines libcurl received while connecting: the greeting, capabilities and the authentication result.
    /// libcurl's commands, which carry the credentials, are never recorded.
    public let connectTranscript: [String]
    private var easy: CurlEasy?
    private let transfer: CurlTransfer
    private let gate: CurlAddressGate
    private let cancellation: CurlCancellation
    private let socket: Int32

    /// Connects and authenticates. Every resolved address is checked before connecting, so credentials are sent
    /// only to an allowed address, and only after TLS is established and verified.
    public static func open(
        server: CurlMailServer, username: String, password: String,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws(CurlMailFailure) -> CurlIMAPSession {
        guard !username.isEmpty else { throw .refused("an IMAP user name is required") }
        let easy: CurlEasy
        do { easy = try CurlEasy() } catch { throw .refused(error.description) }
        let transfer = CurlTransfer(maxBodyBytes: 0, maxHeaderBytes: 262_144, recordsLines: true)
        let gate = CurlAddressGate(policy: server.addresses)
        let cancellation = CurlCancellation()
        do {
            try CurlMailOptions.apply(
                to: easy, server: server, scheme: "imap", path: "", username: username, password: password, gate: gate,
                transfer: transfer, cancellation: cancellation,
                totalTimeoutSeconds: server.connectTimeoutSeconds + Double(server.responseTimeoutSeconds) * 4)
            try easy.set(CURLOPT_CONNECT_ONLY, 1)
        } catch {
            withExtendedLifetime((transfer, gate, cancellation)) { easy.cleanup() }
            throw .refused("the connection could not be prepared: \(error.description)")
        }
        if isCancelled() {
            withExtendedLifetime((transfer, gate, cancellation)) { easy.cleanup() }
            throw .cancelled
        }
        let code = curl_easy_perform(easy.handle)
        guard code == CURLE_OK, let socket = easy.activeSocket() else {
            let failure =
                code == CURLE_OK
                ? CurlMailFailure.connectionLost("libcurl did not hand over a connection")
                : CurlMailOptions.setupFailure(
                    code, message: String(cString: curl_easy_strerror(code)), gate: gate,
                    cancelled: cancellation.isCancelled || isCancelled())
            // libcurl may send LOGOUT and call the header callback while cleaning up a logged-in connection.
            withExtendedLifetime((transfer, gate, cancellation)) { easy.cleanup() }
            throw failure
        }
        return CurlIMAPSession(
            easy: easy, transfer: transfer, gate: gate, cancellation: cancellation, socket: socket,
            transcript: transfer.lines)
    }

    private init(
        easy: CurlEasy, transfer: CurlTransfer, gate: CurlAddressGate, cancellation: CurlCancellation, socket: Int32,
        transcript: [String]
    ) {
        self.easy = easy
        self.transfer = transfer
        self.gate = gate
        self.cancellation = cancellation
        self.socket = socket
        connectTranscript = transcript
    }

    deinit { close() }

    /// Sends all of `bytes` before `deadline`.
    public func send(_ bytes: [UInt8], deadline: Date, isCancelled: () -> Bool = { false }) throws(CurlMailFailure) {
        guard let easy else { throw .connectionLost("the session is closed") }
        var offset = 0
        while offset < bytes.count {
            if isCancelled() { throw .cancelled }
            var sent = 0
            let code = bytes.withUnsafeBytes { buffer in
                curl_easy_send(easy.handle, buffer.baseAddress! + offset, buffer.count - offset, &sent)
            }
            switch code {
            case CURLE_OK:
                offset += sent
            case CURLE_AGAIN:
                try wait(forWriting: true, deadline: deadline, isCancelled: isCancelled)
            default:
                throw .connectionLost("sending failed: \(String(cString: curl_easy_strerror(code)))")
            }
        }
    }

    /// Receives between 1 and `maxBytes` bytes before `deadline`. A closed connection is an error.
    public func receive(maxBytes: Int, deadline: Date, isCancelled: () -> Bool = { false }) throws(CurlMailFailure)
        -> [UInt8]
    {
        guard let easy else { throw .connectionLost("the session is closed") }
        var buffer = [UInt8](repeating: 0, count: max(1, maxBytes))
        while true {
            if isCancelled() { throw .cancelled }
            var received = 0
            let code = buffer.withUnsafeMutableBytes {
                curl_easy_recv(easy.handle, $0.baseAddress, $0.count, &received)
            }
            switch code {
            case CURLE_OK where received == 0:
                throw .connectionLost("the server closed the connection")
            case CURLE_OK:
                return Array(buffer[0..<received])
            case CURLE_AGAIN:
                // Wait only after CURLE_AGAIN: TLS may already hold decrypted data.
                try wait(forWriting: false, deadline: deadline, isCancelled: isCancelled)
            default:
                throw .connectionLost("receiving failed: \(String(cString: curl_easy_strerror(code)))")
            }
        }
    }

    /// Closes the connection. libcurl sends its own LOGOUT and waits at most the server response timeout.
    public func close() {
        guard let easy else { return }
        self.easy = nil
        // Header and progress callbacks can run inside curl_easy_cleanup, so their contexts must outlive it.
        withExtendedLifetime((transfer, gate, cancellation)) { easy.cleanup() }
    }

    private func wait(forWriting: Bool, deadline: Date, isCancelled: () -> Bool) throws(CurlMailFailure) {
        while true {
            if isCancelled() { throw .cancelled }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw .connectionLost("the server did not respond in time") }
            let slice = Int(min(remaining, 0.25) * 1_000) + 1
            switch lisa_curl_wait_socket(socket, forWriting ? 1 : 0, slice) {
            case 1: return
            case 0: continue
            default: throw .connectionLost("the connection failed while waiting")
            }
        }
    }
}
