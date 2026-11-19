// The Mac app's menu commands: a new capture, Settings and Health, a Go menu that opens each screen, and a Host menu
// to try again or restart Lisa's host.

import SwiftUI

/// Keyboard commands (UI-01: keyboard navigation). Command-N starts a capture on Today, Command-Comma opens Settings
/// and Health, and Command-1 to Command-6 open the screens in sidebar order. Each screen adds its own shortcuts, such
/// as Command-R to refresh it.
struct MacCommands: Commands {
    let session: MacSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Capture") { session.navigation.requestCapture() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings and Health…") { session.navigation.show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Go") {
            ForEach(MacSection.allCases) { section in
                Button(section.title) { session.navigation.show(section) }
                    .keyboardShortcut(section.shortcutKey, modifiers: .command)
            }
        }
        CommandMenu("Host") {
            Button("Try Again") {
                Task { await session.retryHost() }
            }
            .disabled(!session.host.mode.canRetry || session.host.isWorking)
            Button("Restart Lisa's Host") {
                Task { await session.restartHost() }
            }
            .disabled(!session.host.mode.isEmbedded || session.host.isWorking)
        }
    }
}
