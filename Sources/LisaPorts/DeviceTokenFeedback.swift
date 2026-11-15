// Provider feedback about device tokens, passed from the delivery outbox to the device registry.

import Foundation
import LisaDomain

/// Receives provider reports that a device token can no longer be used.
public protocol DeviceTokenFeedback: Sendable {
    /// Records that the provider rejected `token` for `deviceID`. `providerTimestamp` is when the provider last
    /// confirmed the token was no longer valid, when it says so; `permanentlyInvalid` marks a malformed token or a
    /// token for the wrong topic.
    func tokenRejected(deviceID: DeviceID, token: String, providerTimestamp: Date?, permanentlyInvalid: Bool) throws
}
