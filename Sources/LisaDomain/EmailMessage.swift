// An email message received in Lisa's own mailbox, with identity, addressing and processing state.

import Foundation

/// An email address with an optional display name. Addresses are stored lower-cased.
public struct EmailAddress: Hashable, Codable, Sendable, CustomStringConvertible {
    public var displayName: String?
    public var address: String

    public init(displayName: String? = nil, address: String) {
        self.displayName = displayName
        self.address = address.lowercased()
    }

    public var description: String {
        if let displayName, !displayName.isEmpty { "\(displayName) <\(address)>" } else { address }
    }
}

/// How the owner relates to a message. Being CC'd does not make every request the owner's task.
public enum OwnerAddressing: String, Codable, Sendable {
    case direct
    case carbonCopy
    case forwardedByOwner
    case sentByOwner
    case unknownSender
}

/// Header facts of a forwarded original message.
public struct ForwardedOriginal: Hashable, Codable, Sendable {
    public var from: EmailAddress?
    public var subject: String?
    public var sentAt: Date?

    public init(from: EmailAddress? = nil, subject: String? = nil, sentAt: Date? = nil) {
        self.from = from
        self.subject = subject
        self.sentAt = sentAt
    }
}

/// Where extraction stands for an item that may need interpretation.
public enum ExtractionState: String, Codable, Sendable {
    case pending
    case extracted
    case awaitingModel
    case failed
}

/// A message in Lisa's mailbox. The body is plain text produced from sanitized MIME content.
public struct EmailMessage: Entity {
    public static let collectionName = "emails"
    public let id: EmailID
    public var revision: Revision
    public var updatedAt: Date
    public var sourceID: SourceID
    /// The source-specific deduplication key, for example `imap:<uidvalidity>:<uid>` or `file:<digest>`.
    public var messageKey: String
    public var messageID: String?
    public var inReplyTo: String?
    public var references: [String]
    public var from: EmailAddress?
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var subject: String
    public var bodyText: String
    public var receivedAt: Date
    public var addressing: OwnerAddressing
    public var forwardedOriginal: ForwardedOriginal?
    /// Attachments that Lisa does not interpret; shown as unsupported.
    public var unsupportedAttachments: [String]
    public var calendarPartCount: Int
    public var evidenceID: EvidenceID
    public var extraction: ExtractionState
    /// Validated reasons the message needs the owner's attention, such as a request for a response.
    public var attention: [String]?
    /// Text the owner wrote: the note above a forward, or the whole body of a message the owner sent. Only this text
    /// can make an extracted commitment confirmed.
    public var ownerNote: String?

    public init(
        id: EmailID = .random(), sourceID: SourceID, messageKey: String, messageID: String?, inReplyTo: String?,
        references: [String], from: EmailAddress?, to: [EmailAddress], cc: [EmailAddress], subject: String,
        bodyText: String, receivedAt: Date, addressing: OwnerAddressing, forwardedOriginal: ForwardedOriginal?,
        unsupportedAttachments: [String], calendarPartCount: Int, evidenceID: EvidenceID, now: Date
    ) {
        self.id = id
        self.revision = .initial
        self.updatedAt = now
        self.sourceID = sourceID
        self.messageKey = messageKey
        self.messageID = messageID
        self.inReplyTo = inReplyTo
        self.references = references
        self.from = from
        self.to = to
        self.cc = cc
        self.subject = subject
        self.bodyText = bodyText
        self.receivedAt = receivedAt
        self.addressing = addressing
        self.forwardedOriginal = forwardedOriginal
        self.unsupportedAttachments = unsupportedAttachments
        self.calendarPartCount = calendarPartCount
        self.evidenceID = evidenceID
        self.extraction = .pending
        self.attention = nil
        self.ownerNote = nil
    }
}
