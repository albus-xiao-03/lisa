// The Today tab at compact width: the rundown or the brief, chosen with a segmented control in the navigation bar.

import SwiftUI

/// Today's rundown and brief in one tab (UI-02: reading the latest rundown and brief).
struct TodayTabView: View {
    let models: CompanionModels
    @Binding var page: CompanionSection

    var body: some View {
        Group {
            if page == .brief {
                BriefView(model: models.brief, speaker: models.speaker)
            } else {
                RundownView(model: models.rundown)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Today", selection: $page) {
                    Text("Rundown").tag(CompanionSection.rundown)
                    Text("Brief").tag(CompanionSection.brief)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }
}
