// The Mac app's screens (UI-01): what each one is called, its symbol and its keyboard shortcut.

import SwiftUI

/// A screen of the Mac app, shown in the sidebar in this order. Command-1 to Command-6 open them.
enum MacSection: CaseIterable, Hashable, Identifiable {
    case today
    case brief
    case inbox
    case ideas
    case memory
    case settings

    var id: Self { self }

    /// The screen's name.
    var title: String {
        switch self {
        case .today: "Today"
        case .brief: "Brief"
        case .inbox: "Inbox"
        case .ideas: "Ideas"
        case .memory: "Memory"
        case .settings: "Settings and Health"
        }
    }

    /// The screen's SF Symbol.
    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .brief: "newspaper"
        case .inbox: "tray"
        case .ideas: "lightbulb"
        case .memory: "brain"
        case .settings: "gearshape"
        }
    }

    /// The key that opens the screen with Command.
    var shortcutKey: KeyEquivalent {
        switch self {
        case .today: KeyEquivalent("1")
        case .brief: KeyEquivalent("2")
        case .inbox: KeyEquivalent("3")
        case .ideas: KeyEquivalent("4")
        case .memory: KeyEquivalent("5")
        case .settings: KeyEquivalent("6")
        }
    }
}
