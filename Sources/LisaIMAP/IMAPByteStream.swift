// The byte stream of an authenticated IMAP session. CurlIMAPSession provides it in production; the command layer
// depends only on this protocol, so it can also run over a scripted stream in tests.

import Foundation
import LisaCurl

/// Blocking sends and receives with deadlines and cancellation checks, used from a single thread.
protocol IMAPByteStream: AnyObject {
    /// Sends all of `bytes` before `deadline`.
    func send(_ bytes: [UInt8], deadline: Date, isCancelled: () -> Bool) throws(CurlMailFailure)
    /// Receives between 1 and `maxBytes` bytes before `deadline`; a closed connection is an error.
    func receive(maxBytes: Int, deadline: Date, isCancelled: () -> Bool) throws(CurlMailFailure) -> [UInt8]
}

extension CurlIMAPSession: IMAPByteStream {}
