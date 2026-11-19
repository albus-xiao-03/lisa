// Test-only. A synthetic invitation: a message with a plain-text part and a `text/calendar` part holding one event,
// which mail ingestion turns into an event proposal without a model (MAIL-01, EVENT-01). Used by L08 and the
// injection suite (L19).

import Foundation

/// Invitation messages.
enum SyntheticInvitation {
    /// A message from `from` to `to` inviting the owner to `event`.
    static func mail(
        _ event: SyntheticEvent, messageID: String, from: String = "Organizer <organizer@example.com>",
        to: String = TestHost.ownerAddress
    ) -> SyntheticMail {
        // The message builder turns every "\n" into CRLF, so the calendar part is written with "\n" only.
        let calendar = SyntheticEvent.calendar([event]).replacingOccurrences(of: "\r\n", with: "\n")
        return SyntheticMail.message(
            subject: "Invitation: \(event.title)", from: from, to: to, messageID: messageID,
            contentType: "multipart/mixed; boundary=\"invitation-parts\"",
            body: SyntheticMail.multipart(
                boundary: "invitation-parts",
                parts: [
                    SyntheticMail.part([("Content-Type", "text/plain; charset=utf-8")], body: "Invitation attached."),
                    SyntheticMail.part(
                        [("Content-Type", "text/calendar; charset=utf-8; method=REQUEST")], body: calendar),
                ]))
    }
}
