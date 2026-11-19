// The compact-width layout (iPhone, and iPad in narrow multitasking sizes): five tabs, each with its own stack.

import LisaPresentation
import SwiftUI

/// Tabs and stacks at compact width (plan §6.5). Today switches between the rundown and the brief; Settings lists the
/// pending actions, connectivity, connection, notification settings and diagnostics, and its badge counts the actions
/// that wait for the host or need the owner's decision.
struct CompanionTabsView: View {
    let session: CompanionSession
    let models: CompanionModels
    @Bindable var navigation: CompanionNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Today", systemImage: "sun.max", value: CompanionTab.today) {
                NavigationStack {
                    TodayTabView(models: models, page: $navigation.todayPage)
                }
            }
            Tab("Capture", systemImage: "square.and.pencil", value: CompanionTab.capture) {
                NavigationStack {
                    CaptureView(model: models.capture)
                }
            }
            Tab("Tasks", systemImage: "checklist", value: CompanionTab.tasks) {
                NavigationStack {
                    TasksView(model: models.tasks)
                }
            }
            Tab("Reminders", systemImage: "bell", value: CompanionTab.reminders) {
                NavigationStack {
                    RemindersView(model: models.reminders)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: CompanionTab.settings) {
                NavigationStack(path: $navigation.settingsPath) {
                    SettingsListView(pendingActions: models.pendingActions)
                        .navigationDestination(for: CompanionSection.self) { section in
                            SectionScreen(section: section, session: session, models: models)
                        }
                }
            }
            .badge(models.pendingActions.pendingCount + models.pendingActions.attentionCount)
        }
    }
}
