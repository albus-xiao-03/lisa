// The companion's commands for a hardware keyboard: a new capture, and a Go menu that opens each screen.

import SwiftUI

/// Keyboard commands (plan §6.5: hardware-keyboard support). Command-N opens Capture, and Command-1 to Command-9 open
/// the screens in sidebar order. Each screen adds its own shortcuts, such as Command-R to refresh it.
struct CompanionCommands: Commands {
    let navigation: CompanionNavigation

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Capture") { navigation.show(.capture) }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Go") {
            ForEach(CompanionSection.allCases) { section in
                if let key = section.shortcutKey {
                    Button(section.title) { navigation.show(section) }
                        .keyboardShortcut(key, modifiers: .command)
                }
            }
        }
    }
}
