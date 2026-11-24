// PROOF ONLY — Apps/Proof never ships. The E-1 probe's cases (plan §8.9.3): for each, the network setup to arrange,
// one field per subcase for the owner's URL or name, a run button, the observed summary, the owner's observation
// where only the owner can see the outcome, and "Finish case". Core is not configured in this app at all.

import SwiftUI

struct FetchProbeView: View {
    @Environment(ProofModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            ForEach(ProbeCase.all) { probeCase in
                Section("\(probeCase.id): \(probeCase.title)") {
                    Text(probeCase.setup).font(.caption)
                    ForEach(probeCase.subcases) { subcase in
                        let key = probeCase.id + "/" + subcase.id
                        TextField(
                            subcase.label,
                            text: Binding(get: { model.fetchInputs[key] ?? "" }, set: { model.fetchInputs[key] = $0 }))
                        Button("Run \(subcase.id)") { Task { await model.runFetch(probeCase, subcase) } }
                        if let summary = model.fetchSummaries[key] { Text(summary).font(.caption.monospaced()) }
                    }
                    if let observation = probeCase.ownerObservation {
                        Picker(
                            observation,
                            selection: Binding(
                                get: { model.ownerObservations[probeCase.id] ?? .notRunEnvironment },
                                set: { model.ownerObservations[probeCase.id] = $0 })
                        ) {
                            Text("not observed").tag(ProofStatus.notRunEnvironment)
                            Text("confirmed").tag(ProofStatus.pass)
                            Text("contradicted").tag(ProofStatus.fail)
                        }
                    }
                    Button("Finish case: write the result record") { model.finishFetchCase(probeCase) }
                }
            }
        }
    }
}
