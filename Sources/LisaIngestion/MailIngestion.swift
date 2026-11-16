// Mail ingestion (MAIL-02): MIME parsing, owner addressing, forwarded originals, evidence, raw content and invitations.

import Foundation
import LisaDomain
import LisaHTMLText
import LisaICalendar
import LisaMIME
import LisaPorts
import LisaTime

/// Stores messages from a mailbox or local mail files. Messages are deduplicated by their stable per-source key and
/// by Message-ID across all sources, so re-fetching or re-importing never stores a message twice.
public struct MailBatchProcessor: BatchProcessor {
    public struct PreparedMessage: Sendable {
        var item: FetchedItem
        var parsed: ParsedMail?
        var rawRef: RawContentRef?
        var problem: String?
    }

    /// Parsed messages plus the settings they are interpreted with, read before the transaction opens.
    public struct PreparedMail: Sendable {
        var messages: [PreparedMessage]
        var ownerAddresses: Set<String>
        var zone: TimeZone
    }

    /// At most this many event proposals are created from one message's calendar parts.
    public static let maxInvitationsPerMessage = 5
    private let store: any RecordStore
    private let raw: any RawContentStore
    private let settings: any SettingsSource
    private let clock: any WallClock
    /// Lisa's own mailbox address; used to tell direct mail from copies.
    private let mailboxAddress: String
    private let limits: MIMELimits

    public init(
        store: any RecordStore, raw: any RawContentStore, settings: any SettingsSource, clock: any WallClock,
        mailboxAddress: String, limits: MIMELimits = MIMELimits()
    ) {
        self.store = store
        self.raw = raw
        self.settings = settings
        self.clock = clock
        self.mailboxAddress = mailboxAddress.lowercased()
        self.limits = limits
    }

    public func prepare(_ batch: FetchBatch, source: Source) throws -> PreparedMail {
        let now = clock.now()
        let owner = try settings.currentSettings()
        let known = try store.read { tx in
            try Set(
                batch.items.filter { item in
                    try tx.first(
                        EmailMessage.self,
                        RecordQuery.all.filter(
                            "dedup_key", equals: EmailMessage.dedupKey(sourceID: source.id, messageKey: item.externalID)
                        ))
                        != nil
                }.map(\.externalID))
        }
        let messages = try batch.items.map { item in
            // Already stored: nothing is parsed or kept again; commit counts it as unchanged.
            if known.contains(item.externalID) { return PreparedMessage(item: item, problem: nil) }
            guard item.kind == .email else {
                return PreparedMessage(item: item, problem: "an item that is not an email was ignored")
            }
            guard item.data.count <= limits.maxMessageBytes else {
                return PreparedMessage(
                    item: item, problem: "a message larger than \(limits.maxMessageBytes) bytes was skipped")
            }
            do {
                let entity = try MIMEParser.parse(item.data, limits: limits)
                let parsed = ParsedMail.from(entity, limits: limits) { HTMLText.convert($0).text }
                let ref = try raw.put(item.data, kind: "email", now: now)
                return PreparedMessage(item: item, parsed: parsed, rawRef: ref)
            } catch let error as StoreError {
                throw error
            } catch {
                return PreparedMessage(item: item, problem: "a message could not be parsed and was skipped")
            }
        }
        return PreparedMail(
            messages: messages, ownerAddresses: Set(owner.delivery.approvedEmailAddresses.map { $0.lowercased() }),
            zone: owner.zone.timeZone)
    }

    public func commit(_ prepared: PreparedMail, batch: FetchBatch, source: Source, in tx: any RecordWriting) throws
        -> IngestionOutcome
    {
        let now = clock.now()
        let ownerAddresses = prepared.ownerAddresses
        var outcome = IngestionOutcome()
        for message in prepared.messages {
            guard let parsed = message.parsed, let rawRef = message.rawRef else {
                if let problem = message.problem {
                    outcome.skipped += 1
                    outcome.warnings.append(problem)
                } else {
                    outcome.unchanged += 1
                }
                continue
            }
            let key = message.item.externalID
            if try tx.first(
                EmailMessage.self,
                RecordQuery.all.filter("dedup_key", equals: EmailMessage.dedupKey(sourceID: source.id, messageKey: key))
            )
                != nil
            {
                outcome.unchanged += 1
                continue
            }
            // Message-IDs are globally unique, so the same message arriving through a second source (for example a
            // local import of a message already fetched by IMAP) is stored once and never re-extracted (L05).
            if let messageID = parsed.messageID,
                try tx.first(EmailMessage.self, RecordQuery.all.filter("message_id", equals: messageID)) != nil
            {
                outcome.unchanged += 1
                continue
            }
            let evidence = try tx.insert(
                Evidence(
                    kind: .email, sourceID: source.id, externalID: key, capturedAt: now, occurredAt: parsed.sentAt,
                    excerpt: String((parsed.subject + " — " + parsed.text).prefix(280)), contentRef: rawRef.value))
            var record = EmailMessage(
                sourceID: source.id, messageKey: key, messageID: parsed.messageID, inReplyTo: parsed.inReplyTo,
                references: parsed.references, from: parsed.from.map(Self.address), to: parsed.to.map(Self.address),
                cc: parsed.cc.map(Self.address), subject: parsed.subject, bodyText: parsed.text,
                receivedAt: message.item.receivedAt, addressing: addressing(parsed, owner: ownerAddresses),
                forwardedOriginal: Self.original(parsed), unsupportedAttachments: parsed.unsupportedAttachments,
                calendarPartCount: parsed.calendarParts.count, evidenceID: evidence.id, now: now)
            record.ownerNote = Self.ownerNote(parsed, addressing: record.addressing)
            let email = try tx.insert(record)
            outcome.inserted += 1
            outcome.pendingReview.append("emails:\(email.id.rawValue)")
            outcome.warnings += parsed.warnings.prefix(3).map { "message \(email.id.rawValue): \($0)" }
            for proposal in try invitations(parsed, evidence: evidence.id, zone: prepared.zone, now: now) {
                let saved = try tx.insert(proposal)
                outcome.changes.append(.proposalChanged(saved.id))
            }
        }
        return outcome
    }

    /// How the owner relates to the message. Copies to the owner are not treated as direct requests.
    func addressing(_ mail: ParsedMail, owner: Set<String>) -> OwnerAddressing {
        let from = mail.from?.address.lowercased()
        if let from, owner.contains(from) {
            return mail.inlineForward != nil || !mail.attachedForwards.isEmpty ? .forwardedByOwner : .sentByOwner
        }
        let to = Set(mail.to.map { $0.address.lowercased() })
        let cc = Set(mail.cc.map { $0.address.lowercased() })
        if !to.isDisjoint(with: owner) { return .direct }
        if !cc.isDisjoint(with: owner) { return .carbonCopy }
        if to.contains(mailboxAddress) { return .direct }
        if cc.contains(mailboxAddress) { return .carbonCopy }
        return .unknownSender
    }

    /// The owner's own words: the note above an inline forward, the outer text around an attached forward, or the
    /// whole body of a message the owner sent.
    static func ownerNote(_ mail: ParsedMail, addressing: OwnerAddressing) -> String? {
        switch addressing {
        case .forwardedByOwner:
            let note = (mail.inlineForward?.note ?? mail.text).trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? nil : note
        case .sentByOwner:
            return mail.text
        case .direct, .carbonCopy, .unknownSender:
            return nil
        }
    }

    static func address(_ address: MailAddress) -> EmailAddress {
        EmailAddress(displayName: address.displayName, address: address.address)
    }

    static func original(_ mail: ParsedMail) -> ForwardedOriginal? {
        if let inline = mail.inlineForward {
            return ForwardedOriginal(from: inline.from.map(address), subject: inline.subject, sentAt: inline.sentAt)
        }
        if let attached = mail.attachedForwards.first {
            return ForwardedOriginal(
                from: attached.from.map(address), subject: attached.subject, sentAt: attached.sentAt)
        }
        return nil
    }

    /// Event proposals from attached invitations: structured data, so no model is involved. Matching against the
    /// calendar happens in review.
    func invitations(_ mail: ParsedMail, evidence: EvidenceID, zone: TimeZone, now: Date) throws -> [EventProposal] {
        var proposals: [EventProposal] = []
        let window = TimeRange(
            uncheckedStart: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(400 * 86_400))
        for part in mail.calendarParts.prefix(Self.maxInvitationsPerMessage) {
            guard let calendar = try? ICalParser.parseCalendar(part) else { continue }
            let expanded = CalendarExpander.expand(
                calendar, options: CalendarExpansionOptions(window: window, floatingZone: zone))
            guard let first = expanded.occurrences.first else { continue }
            var uncertainty = expanded.warnings.map(\.message) + first.warnings
            if first.status == .cancelled { uncertainty.append("the organizer cancelled this event") }
            if expanded.occurrences.count > 1 {
                uncertainty.append("the invitation repeats; the first occurrence is shown")
            }
            let timing: ProposedTiming =
                switch first.times {
                case .timed(let start, let end, let tzid, _):
                    .timed(start: start, end: end, zone: tzid.flatMap(TimeZoneID.init))
                case .allDay(let day, _): .dateOnly(day)
                }
            proposals.append(
                EventProposal(
                    title: String(first.title.prefix(200)), timing: timing, location: first.location,
                    evidenceIDs: [evidence], uncertainty: Array(uncertainty.prefix(5)), now: now))
        }
        return proposals
    }
}
