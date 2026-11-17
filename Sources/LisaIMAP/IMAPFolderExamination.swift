// Opens the configured folder with EXAMINE and confirms what the pass relies on (RFC 9051 §6.3.3, RFC 3501
// §6.3.2): a tagged OK that begins with [READ-ONLY], and the folder's UIDVALIDITY.

import LisaRedaction

/// What EXAMINE reported about the folder.
struct IMAPFolderState: Hashable, Sendable {
    var uidValidity: UInt32
    /// The predicted next UID, when the server reports it (RFC 2060-era servers may not).
    var uidNext: UInt32?
    /// The number of messages, when reported.
    var exists: UInt32?
}

/// EXAMINE and its checks.
enum IMAPFolderExamination {
    static func examine(_ folder: IMAPMailboxName, on channel: IMAPCommandChannel, secret: Sensitive<String>)
        throws(IMAPPassFailure) -> IMAPFolderState
    {
        var uidValidity: UInt32?
        var uidNext: UInt32?
        var exists: UInt32?
        var readWrite = false
        let command = IMAPCommand.examine(folder)
        let completion = try channel.run(command, framing: IMAPPassLimits.smallResponses, wait: .completeResponse) {
            (response: IMAPResponse) throws(IMAPPassFailure) in
            switch response {
            case .exists(let count):
                exists = count
            case .status(.ok, let text):
                switch text.code {
                case .uidValidity(let value):
                    guard uidValidity == nil || uidValidity == value else {
                        throw .failed(.parse, "the IMAP server reported two different UIDVALIDITY values")
                    }
                    uidValidity = value
                case .uidNext(let value):
                    uidNext = value
                case .readWrite:
                    readWrite = true
                default:
                    break
                }
            default:
                break
            }
        }
        guard completion.status == .ok else {
            throw IMAPFailureClassification.refused(command, completion, secret: secret)
        }
        guard completion.text.code == .readOnly, !readWrite else {
            throw .failed(
                .capabilityDenied,
                "the IMAP server did not confirm that the folder was opened read-only ([READ-ONLY]), so Lisa did not "
                    + "read it")
        }
        guard let uidValidity else {
            throw .failed(
                .unsupported,
                "the IMAP server did not report the folder's UIDVALIDITY, so messages cannot be identified")
        }
        return IMAPFolderState(uidValidity: uidValidity, uidNext: uidNext, exists: exists)
    }
}
