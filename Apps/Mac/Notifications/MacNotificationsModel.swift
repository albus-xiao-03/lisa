// Notifications on this Mac: the system's permission for Lisa, asking for it when the owner chooses to, and, with the
// embedded host, this Mac's local-notification installation and the permission it last reported there.

import Foundation
import LisaPresentation
import Observation

/// This Mac's notification status (UI-01: notification status; NOTIFY-05, plan §6.5).
///
/// - The permission is read at launch, on each return to the app and after the owner asks for it. Permission is
///   requested only when the owner chooses Turn On Notifications, never on its own.
/// - With the embedded host, each reading registers this Mac's local-notification installation and reports the
///   permission to it (`LocalInstallation`), so the host suppresses notifications while they are not allowed and
///   resumes once they are. Changes made in System Settings while the app is not running are known at its next launch.
/// - In client mode the host is `lisa serve`, which has no local-notification transport, and this app does not pair as
///   a device, so this Mac receives no Lisa notifications then; `clientModeNote` says so.
@MainActor
@Observable
final class MacNotificationsModel {
    /// The system's permission and settings, once read.
    private(set) var permission: NotificationPermissionStatus?
    /// The embedded host's record of this Mac's installation, while the host runs here.
    private(set) var installation: LocalInstallation.Record?
    /// When the permission was last recorded on the embedded host.
    private(set) var lastReportedAt: Date?
    /// Why the latest request or report did not work, if it did not.
    private(set) var problem: String?
    /// Whether permission is being requested.
    private(set) var isRequesting = false

    @ObservationIgnored private let permissions = SystemNotificationPermissions()
    /// The host and the permission last recorded there, so an unchanged permission is not written again.
    @ObservationIgnored private var recorded: (host: ObjectIdentifier, status: NotificationPermissionStatus)?
    @ObservationIgnored private let host: EmbeddedHostController
    @ObservationIgnored private let credentials: MacOwnerCredentials

    /// What the settings screen says while the app is a client of `lisa serve`.
    static let clientModeNote =
        "While lisa serve runs your host, this Mac gets no Lisa notifications: lisa serve can't post them here, "
        + "and this app connects as the owner rather than pairing as a device for push notifications. Your iPhone "
        + "and iPad still get theirs."

    /// A model over the app's host controller and installation identity.
    init(host: EmbeddedHostController, credentials: MacOwnerCredentials) {
        self.host = host
        self.credentials = credentials
    }

    /// Whether the system allows Lisa's notifications.
    var allowsNotifications: Bool { permission?.allowsNotifications ?? false }

    /// Whether the owner has not been asked yet.
    var canRequestPermission: Bool { permission?.authorization == .notDetermined }

    /// Reads the permission and, with the embedded host, records it for this Mac's installation. Unless `force` is
    /// set, an unchanged permission already recorded on the same host is not written again.
    func refresh(force: Bool = false) async {
        let status = await permissions.currentStatus()
        permission = status
        if force { recorded = nil }
        await report(status)
    }

    /// Asks the system to allow Lisa's notifications (alerts and sounds), at the owner's request, then records the
    /// answer like `refresh()`.
    func requestPermission() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        let status: NotificationPermissionStatus
        do {
            status = try await permissions.requestAuthorization()
        } catch {
            problem = "macOS could not ask for notification permission: \(error.localizedDescription)"
            await refresh()
            return
        }
        permission = status
        problem = nil
        await report(status)
    }

    /// Registers this Mac again under a new installation identifier, after the owner removed its installation from
    /// Lisa's devices.
    func registerAgain() async {
        guard installation?.isActive == false else { return }
        _ = credentials.renewInstallationID()
        recorded = nil
        await refresh()
    }

    /// Records `status` for this Mac's installation on the embedded host, unless that host already has it; without an
    /// embedded host, clears the record shown.
    private func report(_ status: NotificationPermissionStatus) async {
        guard let embedded = host.embeddedHost else {
            installation = nil
            recorded = nil
            return
        }
        let hostID = ObjectIdentifier(embedded)
        if let recorded, recorded.host == hostID, recorded.status == status, installation?.isActive == true { return }
        let local = LocalInstallation(host: embedded, installationID: credentials.installationID)
        let name = ThisAppBuild.pairingDevice()?.name ?? "Mac"
        let bundleIdentifier = ThisAppBuild.bundleIdentifier ?? "unknown"
        do {
            installation = try await Task.detached {
                try local.register(name: name, appBundleID: bundleIdentifier, permission: status)
            }.value
            recorded = (hostID, status)
            lastReportedAt = Date()
            problem = nil
        } catch {
            problem = "Lisa couldn't record this Mac's notification permission on its host: \(error)"
        }
    }
}
