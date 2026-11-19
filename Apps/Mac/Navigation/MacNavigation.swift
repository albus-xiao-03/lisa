// Where the Mac app is: the screen shown, a request to put the cursor in the capture field, and the screen for a
// notification the owner opened.

import LisaAPIContract
import Observation

/// The Mac app's navigation, shared by the window, the menu commands and notifications the owner opens.
@MainActor
@Observable
final class MacNavigation {
    /// The screen shown.
    var section: MacSection? = .today
    /// Whether the capture field on Today should take the keyboard focus; the field clears it once it has.
    var wantsCaptureFocus = false

    /// Shows `section`.
    func show(_ section: MacSection) {
        self.section = section
    }

    /// Shows Today with the cursor in its capture field (New Capture, Command-N).
    func requestCapture() {
        section = .today
        wantsCaptureFocus = true
    }

    /// Shows the screen for the item of a notification the owner opened, by its category, and returns it: reminders,
    /// plan blocks and commitment changes on Today, the brief on Brief, event proposals in the Inbox.
    @discardableResult
    func open(_ item: LisaPushData) -> MacSection {
        let target: MacSection =
            switch NotificationCategoryID(kind: item.kind) {
            case .reminder?, .overdue?, .planBlock?, .commitmentChange?, nil: .today
            case .brief?: .brief
            case .eventProposal?: .inbox
            }
        show(target)
        return target
    }
}
