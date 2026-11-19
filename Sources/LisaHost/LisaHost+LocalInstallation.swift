// The local-notification installation of the app that embeds the host (D-29): registered once per app installation,
// with the notification permission the system reports for it, without an API route.

import Foundation
import LisaAPIContract
import LisaApplication
import LisaDevices
import LisaDomain

extension LisaHost {
    /// Registers the embedding app's local-notification installation, or finds the one registered earlier under
    /// `installationID`, and records `status` for it while it is active (D-29, plan §6.5).
    ///
    /// The host creates one delivery for each active installation, and routes notifications to a local installation
    /// only while the permission it recorded allows them. The installation has no device credential, so no API route
    /// reaches it: the app that supplies the host's platform services, such as the Mac app with its local-notification
    /// transport, calls this instead. A removed installation stays removed, and its permission is not recorded;
    /// registering again needs a new installation identifier. The call writes to the host's store, so callers make it
    /// off the main actor.
    ///
    /// - Parameters:
    ///   - installationID: the app installation's stable identifier; it is not a secret.
    ///   - name: the name the paired-devices list shows.
    ///   - appBundleID: the app's bundle identifier.
    ///   - status: the system's notification permission and settings, as a paired device reports them.
    /// - Returns: what the host records for the installation afterwards.
    public func registerLocalInstallation(
        installationID: String, name: String, appBundleID: String, status: NotificationStatusRequest
    ) throws -> LocalInstallationRecord {
        var registration = try application.services.devices.registerLocalInstallation(
            installationID: installationID, name: name, appBundleID: appBundleID)
        if registration.state == .active {
            registration = try application.reportNotificationStatus(
                deviceID: registration.id,
                authorization: NotificationAuthorization(rawValue: status.authorization.rawValue) ?? .unknown,
                settings: status.settings)
        }
        return LocalInstallationRecord(registration)
    }
}
