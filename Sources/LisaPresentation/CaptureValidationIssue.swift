// Why a capture draft cannot be saved yet: empty, missing or invalid address, or longer than the host accepts.

import Foundation

/// A problem that keeps a capture draft from being saved. The host checks the same rules and stays the authority.
public enum CaptureValidationIssue: Hashable, Sendable {
    /// An idea or text capture has neither text nor an address.
    case emptyText
    /// A link or Apple News share has no address.
    case missingAddress
    /// The address is not an `http` or `https` address with a host.
    case invalidAddress
    /// The text is longer than the host accepts.
    case textTooLong(limit: Int)
    /// The address is longer than the host accepts.
    case addressTooLong(limit: Int)

    /// A sentence for the capture screen; it never repeats what the owner wrote.
    public var message: String {
        switch self {
        case .emptyText: "Write something to capture."
        case .missingAddress: "Add the link to save."
        case .invalidAddress: "The link must be a web address starting with https:// or http://."
        case .textTooLong(let limit): "The text is too long. Lisa saves up to \(limit) characters."
        case .addressTooLong(let limit): "The link is too long. Lisa saves links of up to \(limit) characters."
        }
    }
}
