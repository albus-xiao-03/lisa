// Start at login, as the owner chooses: the app itself registered as a login item with SMAppService, and the status
// macOS reports for it. There is no helper app.

import Foundation
import Observation
import ServiceManagement

/// Whether Lisa opens when the owner logs in (plan Phase 8: optional start at login).
///
/// The app registers itself (`SMAppService.mainApp`) only when the owner turns the option on, and unregisters when it
/// is turned off. macOS may ask the owner to approve it in System Settings → General → Login Items; until then the
/// status is "requires approval", which the screen shows with a way to open those settings.
@MainActor
@Observable
final class LoginItemController {
    /// The status macOS reports.
    private(set) var status: SMAppService.Status = .notRegistered
    /// Why the latest change did not work, if it did not.
    private(set) var problem: String?

    /// Reads the status again, for example when the app becomes active after the owner changed it in System Settings.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    /// Whether the app is registered to open at login, approved or waiting for approval.
    var isRequested: Bool { status == .enabled || status == .requiresApproval }

    /// Whether macOS waits for the owner's approval in System Settings.
    var needsApproval: Bool { status == .requiresApproval }

    /// Registers the app as a login item, or unregisters it.
    func setOpensAtLogin(_ opens: Bool) {
        do {
            if opens {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = "macOS didn't change the login item: \(error.localizedDescription)"
        }
        refresh()
    }

    /// Opens System Settings at the login items, where the owner approves the app.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The status in words.
    var statusText: String {
        switch status {
        case .enabled: "Lisa opens when you log in."
        case .requiresApproval: "Waiting for your approval in System Settings → General → Login Items."
        case .notRegistered: "Lisa doesn't open when you log in."
        case .notFound: "macOS can't find this copy of Lisa. Move Lisa to your Applications folder and try again."
        @unknown default: "macOS reports a login item status Lisa doesn't know."
        }
    }
}
