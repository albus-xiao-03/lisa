// PROOF ONLY — Apps/Proof is the X1 proof app (plan §10.6, §10.8 scheme `LisaProof`). It never ships, is linked by
// no product, and its roster, keys and certificates are synthetic and local.

import SwiftUI

@main
struct LisaProofApp: App {
    @State private var model = ProofModel()

    var body: some Scene {
        WindowGroup {
            ProofRootView()
                .environment(model)
        }
    }
}
