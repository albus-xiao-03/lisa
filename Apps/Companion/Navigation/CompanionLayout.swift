// The companion's adaptive layout: a sidebar and detail at regular width (iPad), tabs with a stack each at compact
// width (iPhone, and iPad in narrow multitasking sizes), and the session events that every screen depends on.

import LisaPresentation
import SwiftUI

/// Chooses the layout from the horizontal size class and keeps the screen shown when the size class changes, as it
/// does when the owner resizes the app in Split View or Stage Manager (plan §6.5).
///
/// It also reacts to the session's events: a notification the owner opened shows its screen; a removal by the host,
/// or unpairing, reads every screen again so that none keeps showing the owner's data; and each action the owner
/// takes rereads the queue, so the pending-actions badge stays current.
struct CompanionLayout: View {
    let session: CompanionSession
    let models: CompanionModels
    @Bindable var navigation: CompanionNavigation
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        layout
            .environment(navigation)
            .onChange(of: sizeClass) { _, newClass in
                if newClass == .compact {
                    navigation.show(navigation.section ?? navigation.compactSection)
                } else {
                    navigation.section = navigation.compactSection
                }
            }
            .onChange(of: session.environment.itemToOpen, initial: true) { _, item in
                guard item != nil, let opened = session.environment.takeItemToOpen() else { return }
                Task { await session.open(opened) }
            }
            .onChange(of: models.connectivity.status) { _, status in
                guard status == .revoked || status == .notPaired else { return }
                Task { await session.clearScreensAfterRemoval() }
            }
            .onChange(of: models.capture.lastOutcome) { reloadQueue() }
            .onChange(of: models.tasks.lastOutcome) { reloadQueue() }
            .onChange(of: models.reminders.lastOutcome) { reloadQueue() }
            .onChange(of: models.notificationSettings.lastOutcome) { reloadQueue() }
            .alert(
                "Review on Your Mac", isPresented: $navigation.isShowingNotice, presenting: navigation.notice,
                actions: { _ in Button("OK", role: .cancel) {} }, message: { notice in Text(notice) })
    }

    @ViewBuilder
    private var layout: some View {
        if sizeClass == .compact {
            CompanionTabsView(session: session, models: models, navigation: navigation)
        } else {
            CompanionSplitView(session: session, models: models, navigation: navigation)
        }
    }

    private func reloadQueue() {
        Task { await models.pendingActions.reload() }
    }
}
