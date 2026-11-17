// Where the companion is: the sidebar's screen at regular width, the tab and its stack at compact width, and a notice
// for a notification whose item the companion does not review.

import LisaAPIContract
import Observation

/// The companion's navigation, shared by both layouts so that a change of size (iPad multitasking) keeps the screen,
/// and used by the keyboard commands and by notifications the owner opens.
@MainActor
@Observable
final class CompanionNavigation {
    /// The screen shown at regular width.
    var section: CompanionSection? = .rundown
    /// The tab shown at compact width.
    var tab: CompanionTab = .today
    /// The screen of the Today tab: `.rundown` or `.brief`.
    var todayPage: CompanionSection = .rundown
    /// The screens pushed on the Settings tab.
    var settingsPath: [CompanionSection] = []
    /// A short notice to show, such as where to review an event a notification was about.
    var notice: String?
    /// Whether `notice` is shown.
    var isShowingNotice = false

    /// Shows `section` in both layouts.
    func show(_ section: CompanionSection) {
        self.section = section
        tab = section.tab
        switch section.tab {
        case .today: todayPage = section
        case .settings: settingsPath = [section]
        case .capture, .tasks, .reminders: break
        }
    }

    /// The screen the compact layout shows, for the sidebar when the width becomes regular.
    var compactSection: CompanionSection {
        switch tab {
        case .today: todayPage
        case .capture: .capture
        case .tasks: .tasks
        case .reminders: .reminders
        case .settings: settingsPath.last ?? .connectivity
        }
    }

    /// Shows the screen for the item of a notification the owner opened, by its category, and returns it. Event
    /// proposals are reviewed in Lisa on the Mac (UI-01), so for those a notice is shown and `nil` returned.
    func open(_ item: LisaPushData) -> CompanionSection? {
        let section: CompanionSection
        switch NotificationCategoryID(kind: item.kind) {
        case .reminder?, .overdue?:
            section = .reminders
        case .planBlock?, .commitmentChange?:
            section = .rundown
        case .brief?:
            section = .brief
        case .eventProposal?:
            notice = "Lisa found an event for you to review. Review it in Lisa on your Mac."
            isShowingNotice = true
            return nil
        case nil:
            section = .rundown
        }
        show(section)
        return section
    }
}
