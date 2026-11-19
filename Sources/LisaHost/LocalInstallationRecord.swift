// What the host records for the local-notification installation of the app that embeds it: its identifier, whether it
// is still registered, whether notifications are routed to it, and the permission it last reported.

import Foundation
import LisaAPIContract
import LisaDomain

/// The host's record of a local-notification installation (D-29), as the app that embeds the host shows it.
public struct LocalInstallationRecord: Hashable, Sendable {
    /// The host's identifier of the installation, as the paired-devices list shows it.
    public var deviceID: String
    /// Whether the installation is still registered; the owner can remove it like any device.
    public var isActive: Bool
    /// Whether the host routes notifications to it now.
    public var canReceiveNotifications: Bool
    /// The notification permission the host last recorded for it.
    public var authorization: NotificationAuthorizationValue

    /// The record of `registration`.
    init(_ registration: DeviceRegistration) {
        deviceID = registration.id.rawValue
        isActive = registration.state == .active
        canReceiveNotifications = registration.canReceiveNotifications
        authorization = NotificationAuthorizationValue(rawValue: registration.authorization.rawValue) ?? .unknown
    }
}
