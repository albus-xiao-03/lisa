// The live delivery adapters a host may use: SMTP email, Twilio calls and APNs pushes. Each is used only for a
// channel whose mode is live; configuring an adapter sends nothing by itself.

import LisaAPNs
import LisaSMTP
import LisaTwilio

/// The configured live delivery adapters.
public struct DeliveryAdapterSettings: Hashable, Sendable {
    public var smtp: SMTPSettings?
    public var twilio: TwilioSettings?
    public var apns: APNsSettings?

    public init(smtp: SMTPSettings? = nil, twilio: TwilioSettings? = nil, apns: APNsSettings? = nil) {
        self.smtp = smtp
        self.twilio = twilio
        self.apns = apns
    }
}
