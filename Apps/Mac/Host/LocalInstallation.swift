// This Mac as the embedded host's local-notification installation (D-29): registered once per app installation, with
// the notification permission the Mac reports, so the host routes local notifications to it.

import Foundation
import LisaApplication
import LisaDevices
import LisaDomain
import LisaHost
import LisaPresentation

/// The Mac's local-notification installation on its embedded host (D-29, plan §6.5).
///
/// The host creates one delivery for each active installation, and routes notifications to a local installation only
/// while it reports that the system allows them. The installation has no device credential, so no API route reaches
/// it: the app, which supplies the host's platform services, calls the host's device service and application facade
/// directly. These calls write to the host's store, so callers make them off the main actor.
struct LocalInstallation: Sendable {
    /// What the host records for the installation.
    struct Record: Hashable, Sendable {
        /// The host's identifier of the installation, as the paired-devices list shows it.
        var deviceID: String
        /// Whether the installation is still registered; the owner can remove it like any device.
        var isActive: Bool
        /// Whether the host routes notifications to it now.
        var canReceiveNotifications: Bool
        /// The permission the host last recorded for it.
        var reportedAuthorization: String
    }

    /// The embedded host.
    let host: LisaHost
    /// This app's installation identifier (`MacOwnerCredentials.installationID`).
    let installationID: String

    /// Registers the installation, or finds the one registered earlier, and records `permission` for it while it is
    /// active. A removed installation stays removed; registering again needs a new installation identifier.
    func register(name: String, appBundleID: String, permission: NotificationPermissionStatus) throws -> Record {
        var registration = try host.application.services.devices.registerLocalInstallation(
            installationID: installationID, name: name, appBundleID: appBundleID)
        if registration.state == .active {
            registration = try host.application.reportNotificationStatus(
                deviceID: registration.id,
                authorization: NotificationAuthorization(rawValue: permission.authorization.rawValue) ?? .unknown,
                settings: permission.settings)
        }
        return Record(
            deviceID: registration.id.rawValue, isActive: registration.state == .active,
            canReceiveNotifications: registration.canReceiveNotifications,
            reportedAuthorization: registration.authorization.rawValue)
    }
}
