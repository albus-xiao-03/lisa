// The companion's screens (UI-02): what each one is called, its symbol, its tab at compact width and its keyboard
// shortcut.

import SwiftUI

/// A screen of the companion. At regular width (iPad) each one is a sidebar item; at compact width (iPhone) they are
/// grouped into the tabs of `CompanionTab`.
enum CompanionSection: CaseIterable, Hashable, Identifiable {
    case rundown
    case brief
    case reminders
    case capture
    case tasks
    case pending
    case connectivity
    case connection
    case notifications
    case diagnostics

    var id: Self { self }

    /// The screen's name.
    var title: String {
        switch self {
        case .rundown: "Rundown"
        case .brief: "Brief"
        case .capture: "Capture"
        case .tasks: "Tasks"
        case .reminders: "Reminders"
        case .pending: "Pending Actions"
        case .connectivity: "Connectivity"
        case .connection: "Connection"
        case .notifications: "Notifications"
        case .diagnostics: "Diagnostics"
        }
    }

    /// The screen's SF Symbol.
    var systemImage: String {
        switch self {
        case .rundown: "calendar.day.timeline.left"
        case .brief: "newspaper"
        case .capture: "square.and.pencil"
        case .tasks: "checklist"
        case .reminders: "bell"
        case .pending: "clock.arrow.circlepath"
        case .connectivity: "antenna.radiowaves.left.and.right"
        case .connection: "link"
        case .notifications: "bell.badge"
        case .diagnostics: "stethoscope"
        }
    }

    /// The tab that holds the screen at compact width.
    var tab: CompanionTab {
        switch self {
        case .rundown, .brief: .today
        case .capture: .capture
        case .tasks: .tasks
        case .reminders: .reminders
        case .pending, .connectivity, .connection, .notifications, .diagnostics: .settings
        }
    }

    /// The key that opens the screen with Command on a hardware keyboard; Diagnostics has none.
    var shortcutKey: KeyEquivalent? {
        switch self {
        case .rundown: KeyEquivalent("1")
        case .brief: KeyEquivalent("2")
        case .reminders: KeyEquivalent("3")
        case .capture: KeyEquivalent("4")
        case .tasks: KeyEquivalent("5")
        case .pending: KeyEquivalent("6")
        case .connectivity: KeyEquivalent("7")
        case .connection: KeyEquivalent("8")
        case .notifications: KeyEquivalent("9")
        case .diagnostics: nil
        }
    }
}
