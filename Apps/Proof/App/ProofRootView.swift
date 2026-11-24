// PROOF ONLY — Apps/Proof never ships. The proof app's four areas, under a permanent proof-only banner.

import SwiftUI

struct ProofRootView: View {
    @Environment(ProofModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Text("PROOF ONLY — synthetic identities, never a production app")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(.orange)
            if !model.message.isEmpty {
                Text(model.message).font(.caption).padding(4)
            }
            TabView {
                RosterView().tabItem { Label("Roster", systemImage: "person.3") }
                NearbyProofView().tabItem { Label("Nearby", systemImage: "antenna.radiowaves.left.and.right") }
                FetchProbeView().tabItem { Label("Fetch", systemImage: "globe") }
                ResultsView().tabItem { Label("Results", systemImage: "list.bullet.clipboard") }
            }
        }
    }
}
